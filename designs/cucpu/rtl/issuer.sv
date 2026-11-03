
module issuer
    import cucpu_common::*;
(
    input logic clk,
    input logic rst_n,
    input instr_t ins,
    input logic ins_valid,
    output logic ins_ready,

    input logic[DW-1:0] rs1_data,
    input logic[DW-1:0] rs2_data,
    input logic[DW-1:0] rs3_data,

    output logic[REG_ADDR_W-1:0] rs1_addr,
    output logic[REG_ADDR_W-1:0] rs2_addr,
    output logic[REG_ADDR_W-1:0] rs3_addr,

    input logic rs1_ready,
    input logic rs2_ready,
    input logic rs3_ready,

    output logic[REG_ADDR_W-1:0] rd_addr,
    input logic rd_ready,

    input logic alloc_ready,
    input logic[COMMIT_SLOT_ADDR_W-1:0] alloc_slot_addr,
    output logic alloc_valid,
    output logic[REG_ADDR_W-1:0] alloc_req,

    output issue_t issue,

    output logic[OP_CODE_W-1:0] exec_op_code,
    input logic exec_ready,
    output exec_valid,
    output logic[DW-1:0] rs1,rs2,rs3,
    output logic[COMMIT_SLOT_ADDR_W-1:0] exec_slot_addr,
    output logic [ALU_MODIFIER_W-1:0] exec_modifiers
);

    instr_t buf_ins;
    reg buf_valid;

    logic [DW-1:0] imm;
    logic rs1_imm,rs2_imm,rs3_imm;

    // 译码，获取操作数寄存器号
    always_comb {

        imm = '0;
        case(buf_ins.op_group)
            OP_GROUP_ALU: {

                alu_payload_t alu_param;
                alu_param = buf_ins.payload.alu;

                rd_addr = alu_param.rd;
                rs1_addr = alu_param.imm_sel==1?0:alu_param.rs1;
                rs2_addr = alu_param.imm_sel==2?0:alu_param.rs2;
                rs3_addr = alu_param.imm_sel==3?0:alu_param.rs3;

                rs1_imm = alu_param.imm_sel==1;
                rs2_imm = alu_param.imm_sel==2;
                rs3_imm = alu_param.imm_sel==3;

                case(alu_param.imm_sel)
                    0: imm = '0;
                    1: imm = {alu_param.rs1,alu_param.imm};
                    2: imm = {alu_param.rs2,alu_param.imm};
                    3: imm = {alu_param.rs3,alu_param.imm};
                endcase


            }
            default: {
                rd_addr = 0;
                rs1_addr = 0;
                rs2_addr = 0;
                rs3_addr = 0;

                rs1_imm = 0;
                rs2_imm = 0;
                rs3_imm = 0;
            }
        endcase

    }

    logic ready_common_cond;
    assign ready_common_cond=rst_n&&buf_valid&&rs1_ready&&rs2_ready&&rs3_ready&&rd_ready;
    
    assign alloc_valid = ready_common_cond&&exec_ready;
    assign alloc_req = rd_addr;

    assign issue.valid = ready_common_cond&&exec_ready&&alloc_ready;
    assign issue.rd = rd_addr;
    assign issue.slot_addr = alloc_slot_addr;

    assign exec_valid = ready_common_cond&&alloc_ready;
    assign rs1 = rs1_imm ? imm : rs1_data;
    assign rs2 = rs2_imm ? imm : rs2_data;
    assign rs3 = rs3_imm ? imm : rs3_data;
    assign exec_op_code = buf_ins.op_code;

    assign ins_ready=rst_n&&(!buf_valid||(exec_valid&&exec_ready));

    always_ff @(posedge clk) {
        if(!rst_n) {
            buf_valid <='0;

        } else {

            if(exec_ready && exec_valid)
            {
                buf_valid <= '0;
            }
            if(ins_valid && ins_ready)
            {
                buf_ins <= ins;
                buf_valid <= '1;
            }
        }
    }
endmodule
