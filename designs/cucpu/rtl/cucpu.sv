
module cucpu
    import cucpu_common::*;
(
    input logic clk,
    input logic rst_n,
    input logic [ADDR_W-1:0] pc_rst,

    // fetcher 尚未实现取指输出，暂由外部指令流驱动。
    input instr_t ins,
    input logic ins_valid,
    output logic ins_ready,
    output commit_t commit
);

    logic [REG_ADDR_W-1:0] rs1_addr, rs2_addr, rs3_addr, rd_addr;
    logic [DW-1:0] rs1_data, rs2_data, rs3_data;
    logic rs1_ready, rs2_ready, rs3_ready, rd_ready;

    logic alloc_valid, alloc_ready;
    logic [REG_ADDR_W-1:0] alloc_req;
    logic [COMMIT_SLOT_ADDR_W-1:0] alloc_slot_addr;
    issue_t issue;

    logic exec_valid, exec_ready;
    logic [OP_CODE_W-1:0] exec_op_code;
    logic [ALU_MODIFIER_W-1:0] exec_modifiers;
    logic [DW-1:0] rs1, rs2, rs3;
    logic [COMMIT_SLOT_ADDR_W-1:0] exec_slot_addr;
    complete_t complete_alu_latancy1, complete_alu_latancy2;
    complete_t complete_alu_latancy3, complete_alu_latancy4;

    logic [COMMIT_SLOT_ADDR_W-1:0] query_rs1, query_rs2, query_rs3;
    commit_slot query_rs1_result, query_rs2_result, query_rs3_result;


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
        .rd_ready,
        .alloc_valid,
        .alloc_ready,
        .alloc_req,
        .alloc_slot_addr,
        .issue,
        .exec_valid,
        .exec_ready,
        .exec_op_code,
        .exec_modifiers,
        .exec_slot_addr,
        .rs1,
        .rs2,
        .rs3
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
        .issue,
        .commit,
        .commit_queue_query_rs1(query_rs1),
        .commit_queue_query_rs2(query_rs2),
        .commit_queue_query_rs3(query_rs3),
        .commit_queue_query_rs1_result(query_rs1_result),
        .commit_queue_query_rs2_result(query_rs2_result),
        .commit_queue_query_rs3_result(query_rs3_result)
    );

    executor_alu executor_alu_inst(
        .clk,
        .rst_n,
        .exec_valid,
        .exec_ready,
        .exec_op_code,
        .exec_modifiers,
        .exec_slot_addr,
        .rs1,
        .rs2,
        .rs3,
        .latancy1_complete(complete_alu_latancy1),
        .latancy2_complete(complete_alu_latancy2),
        .latancy3_complete(complete_alu_latancy3),
        .latancy4_complete(complete_alu_latancy4)
    );

    commit_queue queue_inst(
        .clk,
        .rst_n,
        .alloc_valid,
        .alloc_ready,
        .alloc_req,
        .alloc_slot_addr,
        .complete_alu_latancy1,
        .complete_alu_latancy2,
        .complete_alu_latancy3,
        .complete_alu_latancy4,
        .rs1_query_addr(query_rs1),
        .rs2_query_addr(query_rs2),
        .rs3_query_addr(query_rs3),
        .rs1_query_result(query_rs1_result),
        .rs2_query_result(query_rs2_result),
        .rs3_query_result(query_rs3_result),
        .commit
    );
endmodule
