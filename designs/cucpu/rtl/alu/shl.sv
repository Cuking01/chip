module shl
    import cucpu_common::*;
(
    input logic valid,
    input logic [DW-1:0] rs1,
    input logic [$clog2(DW)-1:0] shamt,
    input logic [COMMIT_SLOT_ADDR_W-1:0] slot_addr,

    output complete_t complete
);
    localparam integer STAGE_NUM = $clog2(DW);
    logic [DW-1:0] stage [0:STAGE_NUM];

    assign stage[0] = rs1;
    // DW=32 时为五层组合选择器，分别可左移 1/2/4/8/16 位。
    for (genvar level = 0; level < STAGE_NUM; level++) begin : shift_stage
        localparam integer SHIFT = 1 << level;
        assign stage[level+1] = shamt[level]
            ? {stage[level][DW-SHIFT-1:0], {SHIFT{1'b0}}}
            : stage[level];
    end

    assign complete.valid = valid;
    assign complete.slot_addr = slot_addr;
    assign complete.result = stage[STAGE_NUM];
endmodule
