module shr
    import cucpu_common::*;
(
    input logic valid,
    input logic [DW-1:0] rs1,
    input logic [$clog2(DW)-1:0] shamt,
    input logic signed_mode,
    input logic [COMMIT_SLOT_ADDR_W-1:0] slot_addr,

    output complete_t complete
);
    localparam integer STAGE_NUM = $clog2(DW);
    logic [DW-1:0] stage [0:STAGE_NUM];
    logic fill;

    assign fill = signed_mode & rs1[DW-1];
    assign stage[0] = rs1;
    // 每层使用同一个原始符号位，逻辑右移补 0，算术右移补符号位。
    for (genvar level = 0; level < STAGE_NUM; level++) begin : shift_stage
        localparam integer SHIFT = 1 << level;
        assign stage[level+1] = shamt[level]
            ? {{SHIFT{fill}}, stage[level][DW-1:SHIFT]}
            : stage[level];
    end

    assign complete.valid = valid;
    assign complete.slot_addr = slot_addr;
    assign complete.result = stage[STAGE_NUM];
endmodule
