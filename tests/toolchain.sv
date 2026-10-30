// Exercise the SV features used by CUCPU against both simulation and synthesis.
`ifndef TOOLCHAIN_LOWERED_TEST
module toolchain_probe
    import cucpu_common::*;
(
    input instr_t ins,
    output instr_t mirrored,
    output alu_op_t op,
    output logic [4:0] rd,
    output logic [26:0] imm,
    output integer latency
);
    assign mirrored = ins;
    assign op = alu_op_t'(ins.op_code);
    assign rd = ins.payload.alu.rd;
    assign imm = ins.payload.alu.imm;
    assign latency = op_latency(op);
endmodule
`endif

module toolchain_tb;
    import cucpu_common::*;
    instr_t ins, mirrored;
    alu_op_t op;
    logic [4:0] rd;
    logic [26:0] imm;
    integer latency;

    toolchain_probe dut (.ins, .mirrored, .op, .rd, .imm, .latency);

    task automatic check_op(input alu_op_t requested, input integer expected);
        ins.op_code = requested;
        #1;
        if (op !== requested || latency !== expected)
            $fatal(1, "op %0d: expected latency %0d, got %0d", requested, expected, latency);
        if (mirrored !== ins || rd !== ins.payload.alu.rd || imm !== ins.payload.alu.imm)
            $fatal(1, "instruction layout mismatch");
    endtask

    initial begin
        if ($bits(instr_t) != 64 || $bits(instr_payload_t) != 56 || $bits(alu_payload_t) != 56)
            $fatal(1, "instruction widths");
        ins = 64'hAB_CD_EF_01_23_45_67_89;
        if (ins.payload.raw !== ins[55:0] ||
            ins.payload.memory !== ins.payload.raw || ins.payload.control !== ins.payload.raw)
            $fatal(1, "union views");
        ins.payload.alu.rd = 5'd17;
        if (ins.payload.raw[48:44] !== 5'd17)
            $fatal(1, "union field update");
        check_op(ALU_OP_INC, 1);
        check_op(ALU_OP_DEC, 1);
        check_op(ALU_OP_IADD, 1);
        check_op(ALU_OP_ISUB, 1);
        check_op(ALU_OP_IMUL_LO, 3);
        check_op(ALU_OP_IMUL_HI, 3);
        check_op(ALU_OP_IMAD_LO, 4);
        check_op(ALU_OP_IMAD_HI, 4);
        check_op(ALU_OP_IADD3, 2);
        check_op(ALU_OP_AND, 1);
        check_op(ALU_OP_OR, 1);
        check_op(ALU_OP_XOR, 1);
        check_op(ALU_OP_NOT, 1);
        check_op(ALU_OP_SHL, 1);
        check_op(ALU_OP_SHR, 1);
        check_op(ALU_OP_SEL, 1);
        check_op(ALU_OP_ILT, 1);
        check_op(ALU_OP_ILE, 1);
        check_op(ALU_OP_IGT, 1);
        check_op(ALU_OP_IGE, 1);
        check_op(ALU_OP_IEQ, 1);
        check_op(ALU_OP_INE, 1);
        $display("PASS: package imports, instruction union, enum casts, 22 operation latencies");
        $finish;
    end
endmodule
