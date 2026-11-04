


module commit_queue
    import cucpu_common::*;
(
    input logic clk,
    input logic rst_n,

    input logic alloc_valid,
    input logic[REG_ADDR_W-1:0] alloc_req,
    output logic alloc_ready,
    output logic[COMMIT_SLOT_ADDR_W-1:0] alloc_slot_addr,

    input complete_t complete_alu_latancy1,
    input complete_t complete_alu_latancy2,
    input complete_t complete_alu_latancy3,
    input complete_t complete_alu_latancy4,

    input logic[COMMIT_SLOT_ADDR_W-1:0] rs1_query_addr,
    input logic[COMMIT_SLOT_ADDR_W-1:0] rs2_query_addr,
    input logic[COMMIT_SLOT_ADDR_W-1:0] rs3_query_addr,

    output commit_slot rs1_query_result,
    output commit_slot rs2_query_result,
    output commit_slot rs3_query_result,

    output commit_t commit
);

    commit_slot queue[COMMIT_SLOT_NUM-1:0];
    reg[COMMIT_SLOT_ADDR_W-1:0] head,tail;
    logic[COMMIT_SLOT_ADDR_W-1:0] tail_next,head_next;

    assign rs1_query_result = queue[rs1_query_addr];
    assign rs2_query_result = queue[rs2_query_addr];
    assign rs3_query_result = queue[rs3_query_addr];

    assign alloc_slot_addr = tail;

    always_comb {
        if(head != tail && queue[head].done)
        {
            head_next = (head+1)&(COMMIT_SLOT_NUM-1);
            commit.valid = rst_n;
            commit.rd = queue[head].rd;
            commit.result = queue[head].res;
        }
        else
        {
            head_next = head;
            commit.valid = '0;
            commit.rd = '0;
            commit.result = '0;
        }
    }

    always_ff @(posedge clk) {
        if(!rst_n) {
            head <= 0;
            tail <= 0;
            alloc_ready <= 0;
            for(integer i = 0;i < COMMIT_SLOT_NUM; i++) {
                queue[i].done <= '0;
            }
        } else {
            if(alloc_ready && alloc_valid)
            {
                queue[tail].rd <= alloc_req;
                queue[tail].done <= 0;
                tail_next = tail + 1;
            }
            else
            {
                tail_next = tail;
            }

            if(complete_alu_latancy1.valid)
            {
                queue[complete_alu_latancy1.slot_addr].done <= 1'b1;
                queue[complete_alu_latancy1.slot_addr].res <= complete_alu_latancy1.result;
            }

            if(complete_alu_latancy2.valid)
            {
                queue[complete_alu_latancy2.slot_addr].done <= 1'b1;
                queue[complete_alu_latancy2.slot_addr].res <= complete_alu_latancy2.result;
            }

            if(complete_alu_latancy3.valid)
            {
                queue[complete_alu_latancy3.slot_addr].done <= 1'b1;
                queue[complete_alu_latancy3.slot_addr].res <= complete_alu_latancy3.result;
            }

            if(complete_alu_latancy4.valid)
            {
                queue[complete_alu_latancy4.slot_addr].done <= 1'b1;
                queue[complete_alu_latancy4.slot_addr].res <= complete_alu_latancy4.result;
            }

            head <= head_next;
            tail <= tail_next & (COMMIT_SLOT_NUM-1);
            alloc_ready <= COMMIT_SLOT_ADDR_W'(tail_next - head_next) < COMMIT_SLOT_NUM - 1;
        }
    }

endmodule
