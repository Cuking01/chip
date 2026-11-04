module executor_alu_tb;
    import cucpu_common::*;

    logic clk = 0;
    logic rst_n = 0;
    logic exec_valid = 0;
    logic [OP_CODE_W-1:0] op_code;
    logic [ALU_MODIFIER_W-1:0] modifiers;
    logic [DW-1:0] a, b, c;
    logic [COMMIT_SLOT_ADDR_W-1:0] slot_addr;
    logic exec_ready;
    complete_t c1, c2, c3, c4;
    logic [DW-1:0] corners [0:8];
    alu_op_t operations [0:9];
    alu_op_t logic_operations [0:4];
    integer checks = 0;
    integer random_seed = 32'h1addcafe;
    logic [DW-1:0] random_a, random_b, random_c;

    always #5 clk = ~clk;

    executor_alu dut(
        .clk, .rst_n, .exec_valid, .exec_op_code(op_code),
        .exec_modifiers(modifiers), .rs1(a), .rs2(b), .rs3(c),
        .exec_slot_addr(slot_addr), .exec_ready,
        .latancy1_complete(c1), .latancy2_complete(c2),
        .latancy3_complete(c3), .latancy4_complete(c4)
    );

    // Reference native SV comparisons, independently of carry/eq implementation.
    function automatic logic [DW-1:0] expected_result(
        input alu_op_t op, input logic [DW-1:0] x, y,
        input logic signed_mode, input logic [DW-1:0] z
    );
        case (op)
            ALU_OP_IADD: expected_result = x + y;
            ALU_OP_ISUB: expected_result = x - y;
            ALU_OP_INC: expected_result = x + 1'b1;
            ALU_OP_DEC: expected_result = x - 1'b1;
            ALU_OP_AND: expected_result = x & y;
            ALU_OP_OR: expected_result = x | y;
            ALU_OP_XOR: expected_result = x ^ y;
            ALU_OP_NOT: expected_result = ~x;
            ALU_OP_SHL: expected_result = x << y[$clog2(DW)-1:0];
            ALU_OP_SHR: begin
                // Keep signed/unsigned branches separate: a mixed ternary can
                // make the arithmetic-shift operand unsigned through context.
                if (signed_mode)
                    expected_result = $signed(x) >>> y[$clog2(DW)-1:0];
                else
                    expected_result = x >> y[$clog2(DW)-1:0];
            end
            ALU_OP_SEL:
                for (int bit_index = 0; bit_index < DW; bit_index++)
                    expected_result[bit_index] = x[bit_index] ? z[bit_index] : y[bit_index];
            ALU_OP_ILT: expected_result = {DW{signed_mode
                ? ($signed(x) < $signed(y)) : (x < y)}};
            ALU_OP_ILE: expected_result = {DW{signed_mode
                ? ($signed(x) <= $signed(y)) : (x <= y)}};
            ALU_OP_IGT: expected_result = {DW{signed_mode
                ? ($signed(x) > $signed(y)) : (x > y)}};
            ALU_OP_IGE: expected_result = {DW{signed_mode
                ? ($signed(x) >= $signed(y)) : (x >= y)}};
            ALU_OP_IEQ: expected_result = {DW{x == y}};
            ALU_OP_INE: expected_result = {DW{x != y}};
            default: expected_result = 'x;
        endcase
    endfunction

    task automatic check_operation(
        input alu_op_t op, input logic [DW-1:0] x, y,
        input logic signed_mode, input logic [DW-1:0] z = '0
    );
        logic [DW-1:0] expected;
        logic [COMMIT_SLOT_ADDR_W-1:0] expected_slot;
        begin
            expected = expected_result(op, x, y, signed_mode, z);
            expected_slot = COMMIT_SLOT_ADDR_W'(checks);
            @(negedge clk);
            exec_valid = 1;
            op_code = op;
            modifiers = '0;
            modifiers[ALU_MOD_SIGNED_BIT] = signed_mode;
            a = x;
            b = y;
            c = z;
            slot_addr = expected_slot;
            @(posedge clk); #1;
            if (exec_ready !== 1 || c1.valid !== 1 ||
                c1.result !== expected || c1.slot_addr !== expected_slot)
                $fatal(1, "op=%0d signed=%b a=%h b=%h c=%h result=%h expected=%h slot=%0d expected_slot=%0d",
                    op, signed_mode, x, y, z, c1.result, expected,
                    c1.slot_addr, expected_slot);
            if (c2.valid !== 0 || c3.valid !== 0 || c4.valid !== 0)
                $fatal(1, "unexpected completion lane");
            checks++;
        end
    endtask

    initial begin
        op_code = '0; modifiers = '0; a = '0; b = '0; c = '0; slot_addr = '0;
        operations[0] = ALU_OP_IADD; operations[1] = ALU_OP_ISUB;
        operations[2] = ALU_OP_INC; operations[3] = ALU_OP_DEC;
        operations[4] = ALU_OP_ILT; operations[5] = ALU_OP_ILE;
        operations[6] = ALU_OP_IGT; operations[7] = ALU_OP_IGE;
        operations[8] = ALU_OP_IEQ; operations[9] = ALU_OP_INE;
        logic_operations[0] = ALU_OP_AND; logic_operations[1] = ALU_OP_OR;
        logic_operations[2] = ALU_OP_XOR; logic_operations[3] = ALU_OP_NOT;
        logic_operations[4] = ALU_OP_SEL;
        corners[0] = 0; corners[1] = 1; corners[2] = 2;
        corners[3] = 32'h7fffffff; corners[4] = 32'h80000000;
        corners[5] = 32'h80000001; corners[6] = 32'hfffffffe;
        corners[7] = 32'hffffffff; corners[8] = 32'h55555555;

        @(posedge clk); #1;
        if (c1.valid !== 0) $fatal(1, "reset valid");
        @(negedge clk); rst_n = 1;
        for (int mode = 0; mode < 2; mode++)
            for (int x = 0; x < 9; x++)
                for (int y = 0; y < 9; y++)
                    for (int op = 0; op < 10; op++)
                        check_operation(operations[op], corners[x], corners[y], mode);
        // Includes zero/full/mixed masks and independently varying SEL sources.
        for (int x = 0; x < 9; x++)
            for (int y = 0; y < 9; y++)
                for (int z = 0; z < 9; z++)
                    for (int op = 0; op < 5; op++)
                        check_operation(logic_operations[op], corners[x], corners[y], 0, corners[z]);
        // All 32 amounts, both signs, and high amount bits that must be ignored.
        for (int mode = 0; mode < 2; mode++)
            for (int x = 0; x < 9; x++)
                for (int amount = 0; amount < 32; amount++) begin
                    check_operation(ALU_OP_SHL, corners[x], amount, mode);
                    check_operation(ALU_OP_SHR, corners[x], amount, mode);
                    check_operation(ALU_OP_SHL, corners[x], 32'hffffffe0 | amount, mode);
                    check_operation(ALU_OP_SHR, corners[x], 32'hffffffe0 | amount, mode);
                end
        for (int pair = 0; pair < 128; pair++) begin
            random_a = $random(random_seed);
            random_b = $random(random_seed);
            random_c = $random(random_seed);
            for (int mode = 0; mode < 2; mode++)
                for (int op = 0; op < 10; op++)
                    check_operation(operations[op], random_a, random_b, mode);
            for (int mode = 0; mode < 2; mode++)
                for (int op = 0; op < 5; op++)
                    check_operation(logic_operations[op], random_a, random_b, mode, random_c);
            for (int mode = 0; mode < 2; mode++) begin
                check_operation(ALU_OP_SHL, random_a, random_b, mode);
                check_operation(ALU_OP_SHR, random_a, random_b, mode);
            end
        end

        // An operation handled elsewhere must not complete on the adder lane.
        @(negedge clk); op_code = ALU_OP_IMAD_LO;
        @(posedge clk); #1;
        if (c1.valid !== 0) $fatal(1, "opcode gating");
        @(negedge clk); exec_valid = 0;
        repeat (3) begin
            @(posedge clk); #1;
            if (c1.valid !== 0) $fatal(1, "bubble valid");
        end
        check_operation(ALU_OP_IGE, 32'h80000000, 32'h7fffffff, 1);
        @(negedge clk); rst_n = 0; exec_valid = 0;
        @(posedge clk); #1;
        if (c1.valid !== 0) $fatal(1, "reset did not invalidate completion");
        $display("PASS: %0d ALU arithmetic/comparison/logic/shift cases, tags, bubbles and reset", checks);
        $finish;
    end
endmodule
