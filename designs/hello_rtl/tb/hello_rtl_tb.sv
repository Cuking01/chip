module hello_rtl_tb;
    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic [7:0] count;

    hello_rtl dut (.clk, .rst_n, .count);

    always #5 clk = ~clk;

    initial begin
        $dumpfile("build/hello_rtl/hello_rtl.vcd");
        $dumpvars(0, hello_rtl_tb);
        #12 rst_n = 1'b1;
        repeat (10) @(posedge clk);
        @(negedge clk);
        if (count !== 8'd10) $fatal(1, "expected 10, got %0d", count);
        $display("PASS: count=%0d", count);
        $finish;
    end
endmodule
