
module executor_alu
    import cucpu_common::*;
(
    input logic clk,
    input logic rst_n,

    input logic exec_valid,
    input logic[OP_CODE_W-1:0] exec_op_code,
    input logic [ALU_MODIFIER_W-1:0] exec_modifiers,
    input logic[DW-1:0] rs1,rs2,rs3,
    input logic[COMMIT_SLOT_ADDR_W-1:0] exec_slot_addr,

    output logic exec_ready,

    output complete_t latancy1_complete,
    output complete_t latancy2_complete,
    output complete_t latancy3_complete,
    output complete_t latancy4_complete
);
    
    reg buf_valid;
    reg[OP_CODE_W-1:0] buf_op_code;
    reg[ALU_MODIFIER_W-1:0] buf_modifiers;
    reg[DW-1:0] buf_rs1,buf_rs2,buf_rs3;
    reg[COMMIT_SLOT_ADDR_W-1:0] buf_slot_addr;

    logic iadd_valid;
    logic [DW-1:0] iadd_rs1, iadd_rs2;
    logic iadd_carry_in;
    logic iadd_carry_out;
    logic iadd_compare_enable, iadd_compare_invert;
    logic compare_eq;
    logic [DW-1:0] compare_bias;
    complete_t iadd_complete;
    complete_t shl_complete, shr_complete;
    logic shl_valid, shr_valid;

    assign exec_ready='1;
    assign compare_eq = (buf_rs1 == buf_rs2);
    // 翻转两边的最高位，将有符号顺序转换为无符号顺序。
    assign compare_bias = {buf_modifiers[ALU_MOD_SIGNED_BIT], {(DW-1){1'b0}}};

    always_comb {
        iadd_valid = 1'b0;
        iadd_rs1 = buf_rs1;
        iadd_rs2 = buf_rs2;
        iadd_carry_in = 1'b0;
        iadd_compare_enable = 1'b0;
        iadd_compare_invert = 1'b0;

        case (alu_op_t'(buf_op_code))
            ALU_OP_IADD, ALU_OP_ISUB, ALU_OP_INC, ALU_OP_DEC,
            ALU_OP_ILT, ALU_OP_ILE, ALU_OP_IGT, ALU_OP_IGE:
                iadd_valid = rst_n && buf_valid;
            default: ;
        endcase

        case (alu_op_t'(buf_op_code))
            ALU_OP_ISUB: {
                iadd_rs2 = ~buf_rs2;
                iadd_carry_in = 1'b1;
            }
            ALU_OP_INC: {
                iadd_rs2 = '0;
                iadd_carry_in = 1'b1;
            }
            ALU_OP_DEC: iadd_rs2 = '1;
            ALU_OP_ILT, ALU_OP_ILE, ALU_OP_IGT, ALU_OP_IGE: {
                iadd_rs1 = buf_rs1 ^ compare_bias;
                iadd_rs2 = ~(buf_rs2 ^ compare_bias);
                iadd_carry_in = 1'b1;
                iadd_compare_enable = 1'b1;
                iadd_compare_invert = (buf_op_code == ALU_OP_ILT)
                                     || (buf_op_code == ALU_OP_ILE);
            }
            default: ;
        endcase
    }

    iadd iadd_inst(
        .valid(iadd_valid),
        .rs1(iadd_rs1),
        .rs2(iadd_rs2),
        .carry_in(iadd_carry_in),
        .compare_enable(iadd_compare_enable),
        .compare_invert(iadd_compare_invert),
        .slot_addr(buf_slot_addr),
        .complete(iadd_complete),
        .carry_out(iadd_carry_out)
    );

    assign shl_valid = rst_n && buf_valid && (buf_op_code == ALU_OP_SHL);
    assign shr_valid = rst_n && buf_valid && (buf_op_code == ALU_OP_SHR);

    shl shl_inst(
        .valid(shl_valid),
        .rs1(buf_rs1),
        .shamt(buf_rs2[$clog2(DW)-1:0]),
        .slot_addr(buf_slot_addr),
        .complete(shl_complete)
    );

    shr shr_inst(
        .valid(shr_valid),
        .rs1(buf_rs1),
        .shamt(buf_rs2[$clog2(DW)-1:0]),
        .signed_mode(buf_modifiers[ALU_MOD_SIGNED_BIT]),
        .slot_addr(buf_slot_addr),
        .complete(shr_complete)
    );

    always_comb {
        latancy1_complete = iadd_complete;
        case (alu_op_t'(buf_op_code))
            ALU_OP_AND, ALU_OP_OR, ALU_OP_XOR, ALU_OP_NOT, ALU_OP_SEL:
                latancy1_complete.valid = rst_n && buf_valid;
            default: ;
        endcase
        case (alu_op_t'(buf_op_code))
            ALU_OP_SHL: latancy1_complete = shl_complete;
            ALU_OP_SHR: latancy1_complete = shr_complete;
            ALU_OP_AND: latancy1_complete.result = buf_rs1 & buf_rs2;
            ALU_OP_OR:  latancy1_complete.result = buf_rs1 | buf_rs2;
            ALU_OP_XOR: latancy1_complete.result = buf_rs1 ^ buf_rs2;
            ALU_OP_NOT: latancy1_complete.result = ~buf_rs1;
            // rs1 为逐位掩码：0 选 rs2，1 选 rs3。
            ALU_OP_SEL:
                latancy1_complete.result = (~buf_rs1 & buf_rs2) | (buf_rs1 & buf_rs3);
            ALU_OP_ILE:
                latancy1_complete.result = iadd_complete.result | {DW{compare_eq}};
            ALU_OP_IGT:
                latancy1_complete.result = iadd_complete.result & {DW{!compare_eq}};
            ALU_OP_IEQ, ALU_OP_INE: {
                latancy1_complete.valid = rst_n && buf_valid;
                latancy1_complete.slot_addr = buf_slot_addr;
                latancy1_complete.result = {DW{compare_eq ^ (buf_op_code == ALU_OP_INE)}};
            }
            default: ;
        endcase
    }
    assign latancy2_complete = '0;
    assign latancy3_complete = '0;
    assign latancy4_complete = '0;
    
    

    always_ff @(posedge clk)
    {
        if(!rst_n)
        {
            buf_valid <='0;
        }
        else
        {
            buf_valid <='0;
            if(exec_valid)
            {
                buf_valid <= '1;
                buf_op_code <= exec_op_code;
                buf_modifiers <= exec_modifiers;
                buf_rs1 <= rs1;
                buf_rs2 <= rs2;
                buf_rs3 <= rs3;
                buf_slot_addr <= exec_slot_addr;
            }
        }
    }

endmodule
