
module fetcher
    import cucpu_common::*;
(
    input logic clk,
    input logic rst_n,
    input logic[ADDR_W-1:0] pc_rst
);

    reg[ADDR_W-1:0] pc;

    always_ff @(posedge clk) {
        if(!rst_n) {
            pc <= pc_rst;
        } else {

        }
    }

endmodule
