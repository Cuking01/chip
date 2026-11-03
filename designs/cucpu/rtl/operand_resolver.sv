
module operand_resolver
    import cucpu_common::*;
(
    input logic clk,
    input logic rst_n,

    input logic[REG_ADDR_W-1:0] rs1_addr,
    input logic[REG_ADDR_W-1:0] rs2_addr,
    input logic[REG_ADDR_W-1:0] rs3_addr,

    output logic[DW-1:0] rs1_data,
    output logic[DW-1:0] rs2_data,
    output logic[DW-1:0] rs3_data,

    // 最新操作数是否可用，包括 RF 和 forwarding 的结果。
    output logic rs1_ready,
    output logic rs2_ready,
    output logic rs3_ready,

    // 候选指令的目标查询；ready 表示没有 WAW 阻塞。
    input logic[REG_ADDR_W-1:0] rd_addr,
    output logic rd_ready,

    input issue_t issue,
    input commit_t commit,

    output logic[COMMIT_SLOT_ADDR_W-1:0] commit_queue_query_rs1,
    output logic[COMMIT_SLOT_ADDR_W-1:0] commit_queue_query_rs2,
    output logic[COMMIT_SLOT_ADDR_W-1:0] commit_queue_query_rs3,

    input commit_slot commit_queue_query_rs1_result,
    input commit_slot commit_queue_query_rs2_result,
    input commit_slot commit_queue_query_rs3_result

);

    // RF 原始读数，后续与 forwarding 数据一起选择最终操作数。
    logic [DW-1:0] rf_rs1_data, rf_rs2_data, rf_rs3_data;

    regfile rf_inst(
        .clk,
        .rst_n,
        .rs1_addr,                                                                                                                                                  
        .rs2_addr,
        .rs3_addr,
        .rs1_data(rf_rs1_data),
        .rs2_data(rf_rs2_data),
        .rs3_data(rf_rs3_data),
        .rd_valid(rst_n && commit.valid),
        .rd_addr(commit.rd),
        .rd_data(commit.result)
    );

    reg                           pending[REG_NUM-1:0];   // 寄存器是否等待被写入
    reg[COMMIT_SLOT_ADDR_W-1:0]   producer[REG_NUM-1:0];  // 被哪个槽写入

    assign commit_queue_query_rs1=producer[rs1_addr];
    assign commit_queue_query_rs2=producer[rs2_addr];
    assign commit_queue_query_rs3=producer[rs3_addr];

    assign rs1_data=pending[rs1_addr]?commit_queue_query_rs1_result.res:rf_rs1_data;
    assign rs2_data=pending[rs2_addr]?commit_queue_query_rs2_result.res:rf_rs2_data;
    assign rs3_data=pending[rs3_addr]?commit_queue_query_rs3_result.res:rf_rs3_data;

    assign rs1_ready=~pending[rs1_addr]|commit_queue_query_rs1_result.done;
    assign rs2_ready=~pending[rs2_addr]|commit_queue_query_rs2_result.done;
    assign rs3_ready=~pending[rs3_addr]|commit_queue_query_rs3_result.done;

    assign rd_ready = (rd_addr == '0) || !pending[rd_addr];

    always_ff @(posedge clk) {
        if(!rst_n)
        {
            for (int i = 0; i < REG_NUM; i++)
            {
                pending[i]  <= 1'b0;
                producer[i] <= '0;
            }
        }
        else
        {
            if(commit.valid)
            {
                pending[commit.rd] <= 0;
                producer[commit.rd] <= commit.slot_addr;
            }

            if(issue.valid)
            {
                pending[issue.rd] <= |issue.rd;         //r0不实际记录依赖
                producer[issue.rd] <= issue.slot_addr;
            }


        }
    }

endmodule
