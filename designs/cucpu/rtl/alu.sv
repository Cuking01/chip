module alu
    import cucpu_common::*;
#(parameter integer WIDTH = DW)
(
    input logic clk,
    input logic rst_n,
    input alu_op_t op,
    output logic[WIDTH-1:0] dst,
    input logic[WIDTH-1:0] rs1,
    input logic[WIDTH-1:0] rs2,
    input logic[WIDTH-1:0] rs3,
    input logic[ALU_MODIFIER_W-1:0] modifiers
);


endmodule
