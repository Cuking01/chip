#!/usr/bin/env python3
"""Stage HDL files and translate the workspace's limited brace-block syntax."""

import argparse
import json
import re
import subprocess
from pathlib import Path


# Keep strings, comments and escaped identifiers opaque. Offsets let us replace
# just brace characters without changing whitespace or source line numbers.
TOKEN = re.compile(
    r'//[^\n]*|/\*[\s\S]*?\*/|"(?:\\[\s\S]|[^"\\])*"'
    r"|(?:[0-9][0-9_]*)?'[sS]?[bBoOdDhH][0-9a-fA-F_xXzZ?]+|'[01xXzZ]"
    r'|\\[^\s]+|[A-Za-z_$][A-Za-z0-9_$]*|[^\s]'
)


def convert_blocks(source):
    stack = []
    replacements = {}
    previous = None
    colon_is_label = False
    parentheses = brackets = 0
    ternaries = {}
    matches = [match for match in TOKEN.finditer(source)
               if not match.group().startswith(("//", "/*"))]
    for index, match in enumerate(matches):
        token = match.group()
        context = (parentheses, brackets, len(stack))
        if token == "?":
            ternaries[context] = ternaries.get(context, 0) + 1
        elif token == ":":
            following = matches[index + 1].group() if index + 1 < len(matches) else None
            scope_separator = previous == ":" or following == ":"
            conditional = not scope_separator and ternaries.get(context, 0) > 0
            if conditional:
                ternaries[context] -= 1
            colon_is_label = (not scope_separator and not conditional
                              and parentheses == 0 and brackets == 0)
        if token == "{":
            # Concatenations/replications can contain a brace following ')'.
            # Never translate braces inside an expression-brace context.
            block = (previous in (")", "else", "always_comb")
                     or (previous == ":" and colon_is_label))
            block = block and (not stack or stack[-1][1])
            stack.append((match.start(), block))
        elif token == "}" and stack:
            ternaries.pop(context, None)
            opening, block = stack.pop()
            if block:
                replacements[opening] = " begin "
                replacements[match.start()] = " end "
        if token == "(":
            parentheses += 1
        elif token == ")":
            ternaries.pop(context, None)
            parentheses -= 1
        elif token == "[":
            brackets += 1
        elif token == "]":
            ternaries.pop(context, None)
            brackets -= 1
        elif token == ";":
            ternaries.pop(context, None)
        previous = token
    if any(block for _, block in stack):
        raise ValueError("unmatched opening brace in a brace statement block")
    parts = []
    start = 0
    for offset, replacement in sorted(replacements.items()):
        parts.extend((source[start:offset], replacement))
        start = offset + 1
    parts.append(source[start:])
    return "".join(parts)


def stage_sources(sources, output, include_dirs=()):
    """Mirror source/header directories; return staged sources and include paths."""
    output = Path(output).resolve()
    sources = [Path(path).resolve() for path in sources]
    directories = list(dict.fromkeys(
        [path.parent for path in sources] + [Path(p).resolve() for p in include_dirs]
    ))

    def target(path):
        return output / path.relative_to(path.anchor)

    files = set(sources)
    for directory in directories:
        for pattern in ("*.vh", "*.svh"):
            files.update(path.resolve() for path in directory.rglob(pattern)
                         if not path.resolve().is_relative_to(output))
    for path in sorted(files):
        destination = target(path)
        destination.parent.mkdir(parents=True, exist_ok=True)
        try:
            original = path.read_text()
            converted = convert_blocks(original)
        except ValueError as error:
            raise ValueError(f"{path}: {error}") from error
        if converted != original:
            # Tell compiler diagnostics to refer to the original source.
            converted = f'`line 1 {json.dumps(str(path))} 0\n' + converted
        destination.write_text(converted)
    return ([str(target(path)) for path in sources],
            [str(target(path)) for path in directories])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--filelist", required=True, type=Path)
    parser.add_argument("--iverilog-top")
    parser.add_argument("--iverilog-output", type=Path)
    parser.add_argument("sources", nargs="+")
    args = parser.parse_args()
    sources, includes = stage_sources(args.sources, args.output)
    entries = [json.dumps(item) for item in
               ["-I" + directory for directory in includes] + sources]
    args.filelist.write_text("\n".join(entries) + "\n")
    if bool(args.iverilog_top) != bool(args.iverilog_output):
        parser.error("--iverilog-top and --iverilog-output must be specified together")
    if args.iverilog_top:
        # Icarus command-file quoting differs from slang. Use argv directly,
        # which also preserves spaces in source and include paths.
        subprocess.run(["iverilog", "-g2012", "-Wall", "-s", args.iverilog_top,
                        "-o", str(args.iverilog_output)] +
                       ["-I" + directory for directory in includes] + sources,
                       check=True)


if __name__ == "__main__":
    main()
