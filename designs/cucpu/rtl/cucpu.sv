
module cucpu
    import cucpu_common::*;
(
    input logic clk,
    input logic rst_n,
    input logic [ADDR_W-1:0] pc_rst
);

    logic [REG_ADDR_W-1:0] rs1_addr, rs2_addr, rs3_addr, rd_addr;
    logic [DW-1:0] rs1_data, rs2_data, rs3_data;
    logic rs1_ready, rs2_ready, rs3_ready, rd_ready;

    instr_t ins;
    logic ins_valid;
    logic ins_ready;


    fetcher fetcher_inst(.clk,.rst_n,.pc_rst);
    issuer issuer_inst(
        .clk,
        .rst_n,
        .ins,
        .ins_valid,
        .ins_ready,
        .rs1_data,
        .rs2_data,
        .rs3_data,
        .rs1_addr,
        .rs2_addr,
        .rs3_addr,
        .rs1_ready,
        .rs2_ready,
        .rs3_ready,
        .rd_addr,
        .rd_ready
    );
    operand_resolver resolver_inst(
        .clk,
        .rst_n,
        .rs1_addr,
        .rs2_addr,
        .rs3_addr,
        .rs1_data,
        .rs2_data,
        .rs3_data,
        .rs1_ready,
        .rs2_ready,
        .rs3_ready,
        .rd_addr,
        .rd_ready,
        // 待接入成功发射和提交事件。
        .issue(),
        .commit()
    );
    //executor executor_inst;
endmodule
