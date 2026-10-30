"""Check brace translation and compile its output with the RTL toolchain."""

import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from prepare_sv import convert_blocks, stage_sources


class BraceTests(unittest.TestCase):
    def test_nested_blocks_and_else(self):
        source = "if(a){if(b){x=1;}else{x=2;}}else if(c){x=3;}else{x=4;}"
        result = convert_blocks(source)
        self.assertEqual(result.count("begin"), 5)
        self.assertEqual(result.count("end"), 5)
        self.assertNotIn("{", result)
        self.assertIn(" end else", result)

    def test_expression_braces(self):
        source = "x={a,b}; y={(2){a}}; z={2{f(a)}}; s='{a:1};"
        self.assertEqual(convert_blocks(source), source)
        mixed = "if(a){x={(2){a}};}else{x={a,b};}"
        self.assertIn("{(2){a}}", convert_blocks(mixed))
        self.assertIn("{a,b}", convert_blocks(mixed))

    def test_comments_strings_and_escaped_identifiers(self):
        source = r'''// if(a){ignore}
/* else {ignore} */
if(a) /* comment with } */ {s="else { \" }"; \else {x};}
'''
        result = convert_blocks(source)
        self.assertIn("// if(a){ignore}", result)
        self.assertIn("/* else {ignore} */", result)
        self.assertIn(r'"else { \" }"', result)
        self.assertIn(r'\else {x}', result)
        self.assertEqual(result.count("begin"), 1)
        self.assertEqual(source.count("\n"), result.count("\n"))

    def test_keyword_boundary_and_other_blocks(self):
        source = "myelse {a}; initial {b}; myalways_comb {c};"
        self.assertEqual(convert_blocks(source), source)

    def test_always_comb_and_case_labels(self):
        source = "always_comb{case(a) 4'b?001:{x=1;} default:{x=0;} endcase}"
        result = convert_blocks(source)
        self.assertEqual(result.count("begin"), 3)
        self.assertEqual(result.count("end "), 3)
        self.assertIn("4'b?001:", result)

    def test_colons_in_expressions(self):
        source = """always_comb{
x = a ? {b,c} : {d,e};
x = a ? b ? {c,d} : {e,f} : {g,h};
x = bits[7:0];
x = a ? (b ? c : d) : {e,f};
x = pkg::value;
s = '{field: {a,b}};
case(a) default:{x={a,b};} endcase
}"""
        result = convert_blocks(source)
        self.assertEqual(result.count("begin"), 2)
        for expression in ("{d,e}", "{e,f}", "{g,h}", "bits[7:0]",
                           "pkg::value", "'{field: {a,b}}"):
            self.assertIn(expression, result)

    def test_unmatched_block(self):
        with self.assertRaisesRegex(ValueError, "unmatched"):
            convert_blocks("if(a){x=1;")

    def test_idempotent(self):
        converted = convert_blocks("if(a){x={a,b};}else{x=0;}")
        self.assertEqual(convert_blocks(converted), converted)

    @unittest.skipUnless(shutil.which("iverilog") and shutil.which("yosys"),
                         "requires RTL container tools")
    def test_staging_and_hdl_behavior(self):
        with tempfile.TemporaryDirectory(prefix="brace test-") as directory:
            root = Path(directory)
            source = root / "probe.sv"
            header = root / "body.svh"
            source.write_text('''module brace_probe(input logic [3:0] a,
output logic [7:0] y);
`include "body.svh"
endmodule
module tb;
logic [3:0] a; wire [7:0] y;
brace_probe dut(a,y);
initial begin
a=1; #1; if(y!==8'h11) $fatal(1,"repeat concat");
a=2; #1; if(y!==8'h20) $fatal(1,"else concat");
$display("PASS: brace blocks and preserved expressions"); $finish;
end
endmodule
''')
            header.write_text('''always_comb {
case(a[0])
1'b1: {y={(2){a}};}
default: {y = a[0] ? {4'b0,a} : {a,4'b0};}
endcase
}
''')
            original_source, original_header = source.read_text(), header.read_text()
            paths, includes = stage_sources([source], root / "generated")
            filelist = root / "sources.f"
            subprocess.run([sys.executable,
                            str(Path(__file__).resolve().parents[1] / "scripts" / "prepare_sv.py"),
                            "--output", str(root / "generated"),
                            "--filelist", str(filelist),
                            "--iverilog-top", "tb",
                            "--iverilog-output", str(root / "test.vvp"),
                            str(source)], check=True)
            subprocess.run(["vvp", str(root / "test.vvp")], check=True)
            filelist.write_text("\n".join(json.dumps(p) for p in
                                         ["-I" + p for p in includes] + paths) + "\n")
            # Pass the command file through an unambiguous path to Yosys.
            slang_filelist = root.parent / (root.name.replace(" ", "-") + ".f")
            slang_filelist.write_text(filelist.read_text())
            result = subprocess.run(["yosys", "-Q", "-T", "-p",
                                     f"read_slang -f {slang_filelist} --top brace_probe; check"],
                                    text=True, stdout=subprocess.PIPE,
                                    stderr=subprocess.STDOUT)
            self.assertEqual(result.returncode, 0, result.stdout)
            slang_filelist.unlink()
            self.assertEqual(source.read_text(), original_source)
            self.assertEqual(header.read_text(), original_header)


if __name__ == "__main__":
    unittest.main()
