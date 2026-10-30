
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
    input logic rd_ready
);



    logic [DW-1:0] rs1,rs2,rs3;
    logic [DW-1:0] imm;
    logic rs1_imm,rs2_imm,rs3_imm;


    // 获取操作数寄存器号
    always_comb {

        imm = '0;
        case(ins.op_group)
            OP_GROUP_ALU: {

                alu_payload_t alu_param;
                alu_param = ins.payload.alu;

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

    assign rs1 = rs1_imm ? imm : rs1_data;
    assign rs2 = rs2_imm ? imm : rs2_data;
    assign rs3 = rs3_imm ? imm : rs3_data;

    always_ff @(posedge clk) {
        if(!rst_n) {

            ins_ready <= 0;
        } else {



        }
    }
endmodule
