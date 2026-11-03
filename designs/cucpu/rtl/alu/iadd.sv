module iadd
    import cucpu_common::*;
(
    input logic valid,
    input logic [DW-1:0] rs1,
    input logic [DW-1:0] rs2,
    input logic carry_in, // 为 1 时额外加 1；减法使用 ~rs2 和 carry_in=1。
    input logic compare_enable,
    input logic compare_invert,
    input logic [COMMIT_SLOT_ADDR_W-1:0] slot_addr,

    output complete_t complete,
    output logic carry_out
);
    logic [DW-1:0] sum;

    assign complete.valid = valid;
    assign complete.slot_addr = slot_addr;
    // 扩展一位保留进位；complete.result 仍是 DW 位低位结果。
    // 减法 a + ~b + 1 时，carry_out=1 表示没有借位，即无符号 a>=b。
    assign {carry_out, sum} = {1'b0, rs1} + {1'b0, rs2} + carry_in;
    // 比较模式广播 >= 或其反值 <；eq 边界由调用方独立处理。
    assign complete.result = compare_enable
        ? {DW{carry_out ^ compare_invert}} : sum;
endmodule
