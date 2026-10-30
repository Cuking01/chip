module regfile
    import cucpu_common::*;
#(parameter integer WIDTH = DW,parameter integer SIZE = REG_NUM,parameter bit r0_is_zero = 1'b1)
(
    input  logic clk,
    input  logic rst_n,

    input  logic [REG_ADDR_W-1:0] rs1_addr,
    input  logic [REG_ADDR_W-1:0] rs2_addr,
    input  logic [REG_ADDR_W-1:0] rs3_addr,
    output logic [WIDTH-1:0] rs1_data,
    output logic [WIDTH-1:0] rs2_data,
    output logic [WIDTH-1:0] rs3_data,

    input  logic rd_valid,
    input  logic [REG_ADDR_W-1:0] rd_addr,
    input  logic [WIDTH-1:0] rd_data
);

    reg[WIDTH-1:0] regs[SIZE-1:0];

    assign rs1_data=regs[rs1_addr];
    assign rs2_data=regs[rs2_addr];
    assign rs3_data=regs[rs3_addr];

    always_ff @( posedge clk ) {
        if(!rst_n) {
            for(integer i = 0;i < SIZE ;i++) {
                regs[i] <= '0;
            }
        } else {
            if(rd_valid&&(rd_addr!=0||!r0_is_zero)) {
                regs[rd_addr] <= rd_data;
            }
        }
    }
endmodule
