module cucpu_tb;
    import cucpu_common::*;

    localparam integer MAX_INS = 512;
    logic clk = 0;
    logic rst_n = 0;
    instr_t ins;
    logic ins_valid, ins_ready;
    commit_t commit;
    logic [IW-1:0] rom [0:MAX_INS-1];
    logic [REG_ADDR_W-1:0] expected_rd [0:MAX_INS-1];
    logic [DW-1:0] expected_result [0:MAX_INS-1];
    logic [DW-1:0] model_rf [0:REG_NUM-1];
    logic model_pending [0:REG_NUM-1];
    alu_op_t operations [0:18];
    logic [OP_CODE_W-1:0] expected_op [0:MAX_INS-1];
    integer expected_latency [0:MAX_INS-1];
    integer issued_cycle [0:MAX_INS-1];
    integer slot_instruction [0:COMMIT_SLOT_NUM-1];
    logic completion_seen [0:MAX_INS-1];
    integer length = 0;
    integer main_length;
    integer fetched = 0, issued = 0, committed = 0, cycles = 0;
    integer fetch_stalls = 0, raw_stalls = 0, waw_stalls = 0;
    integer forwarded = 0, wraps = 0, source_bubbles = 0;
    integer multi_complete = 0, younger_first = 0, full_stalls = 0;
    integer mul_raw_stalls = 0, mul_waw_stalls = 0;
    integer mul_consumer_index, mul_waw_index;
    integer mul_stream_start, mul_stream_end;
    integer seed = 32'hc0c00afe;
    logic [31:0] random_value;
    issue_t observed_issue;
    complete_t observed_c1, observed_c3;
    logic stalled_last_cycle = 0;
    logic model_buf_valid = 0;
    instr_t stalled_ins;
    string wave_path;

    always #5 clk = ~clk;
    cucpu dut(.clk, .rst_n, .pc_rst('0), .ins, .ins_valid, .ins_ready, .commit);
    // Observe protocol/coverage; the commit results use an independent RF model.
    assign observed_issue = dut.issue;
    assign observed_c1 = dut.complete_alu_latancy1;
    assign observed_c3 = dut.complete_alu_latancy3;

    // Mock fetcher: advance ROM only on a handshake and hold stalled requests.
    // Readback instructions wait until the main program has fully committed.
    assign ins = fetched < length ? rom[fetched] : '0;
    assign ins_valid = rst_n && fetched < length
        && (fetched < main_length || committed >= main_length)
        && (stalled_last_cycle || cycles < 40 || cycles % 11 != 0
            || (fetched >= mul_stream_start && fetched <= mul_stream_end));

    function automatic logic [DW-1:0] execute_reference(
        input alu_op_t op, input logic [DW-1:0] a, b, c,
        input logic signed_mode
    );
        logic [DW*2-1:0] product;
        product = {{DW{1'b0}},a} * {{DW{1'b0}},b};
        case (op)
            ALU_OP_INC: execute_reference = a + 1;
            ALU_OP_DEC: execute_reference = a - 1;
            ALU_OP_IADD: execute_reference = a + b;
            ALU_OP_ISUB: execute_reference = a - b;
            ALU_OP_IMUL_LO: execute_reference = product[DW-1:0];
            ALU_OP_IMUL_HI: execute_reference = product[DW*2-1:DW];
            ALU_OP_AND: execute_reference = a & b;
            ALU_OP_OR: execute_reference = a | b;
            ALU_OP_XOR: execute_reference = a ^ b;
            ALU_OP_NOT: execute_reference = ~a;
            ALU_OP_SEL:
                for (int bit_index = 0; bit_index < DW; bit_index++)
                    execute_reference[bit_index] = a[bit_index] ? c[bit_index] : b[bit_index];
            ALU_OP_SHL: execute_reference = a << b[4:0];
            ALU_OP_SHR: begin
                if (signed_mode) execute_reference = $signed(a) >>> b[4:0];
                else execute_reference = a >> b[4:0];
            end
            ALU_OP_ILT: execute_reference = {DW{signed_mode
                ? ($signed(a) < $signed(b)) : (a < b)}};
            ALU_OP_ILE: execute_reference = {DW{signed_mode
                ? ($signed(a) <= $signed(b)) : (a <= b)}};
            ALU_OP_IGT: execute_reference = {DW{signed_mode
                ? ($signed(a) > $signed(b)) : (a > b)}};
            ALU_OP_IGE: execute_reference = {DW{signed_mode
                ? ($signed(a) >= $signed(b)) : (a >= b)}};
            ALU_OP_IEQ: execute_reference = {DW{a == b}};
            ALU_OP_INE: execute_reference = {DW{a != b}};
            default: $fatal(1, "unsupported reference opcode %0d", op);
        endcase
    endfunction

    task automatic append_instruction(
        input alu_op_t op,
        input logic [REG_ADDR_W-1:0] rd, r1, r2, r3,
        input logic [1:0] imm_sel = 0,
        input logic [DW-1:0] immediate = 0,
        input logic signed_mode = 0
    );
        instr_t encoded;
        alu_payload_t payload;
        logic [DW-1:0] a, b, c, result;
        begin
            if (length >= MAX_INS) $fatal(1, "ROM capacity exceeded");
            payload = '0;
            payload.rd = rd;
            payload.rs1 = r1; payload.rs2 = r2; payload.rs3 = r3;
            payload.imm_sel = imm_sel;
            payload.imm = immediate[26:0];
            payload.modifiers[ALU_MOD_SIGNED_BIT] = signed_mode;
            // Immediate includes the selected operand's five raw register bits.
            case (imm_sel)
                1: payload.rs1 = immediate[31:27];
                2: payload.rs2 = immediate[31:27];
                3: payload.rs3 = immediate[31:27];
                default: ;
            endcase
            encoded.op_group = OP_GROUP_ALU;
            encoded.op_code = op;
            encoded.payload.alu = payload;
            rom[length] = encoded;

            a = imm_sel == 1 ? immediate : model_rf[r1];
            b = imm_sel == 2 ? immediate : model_rf[r2];
            c = imm_sel == 3 ? immediate : model_rf[r3];
            result = execute_reference(op, a, b, c, signed_mode);
            expected_rd[length] = rd;
            expected_result[length] = result;
            expected_op[length] = op;
            expected_latency[length] = (op == ALU_OP_IMUL_LO || op == ALU_OP_IMUL_HI) ? 3 : 1;
            completion_seen[length] = 0;
            if (rd != 0) model_rf[rd] = result;
            length++;
        end
    endtask

    task automatic check_completion(input complete_t response);
        integer index;
        begin
            if (response.valid) begin
                index = slot_instruction[response.slot_addr];
                if (index < 0 || index >= issued) $fatal(1, "completion without allocation");
                if (completion_seen[index]) $fatal(1, "duplicate completion for instruction %0d", index);
                if (response.result !== expected_result[index] ||
                    cycles - issued_cycle[index] != expected_latency[index])
                    $fatal(1, "completion %0d op=%0d result=%h expected=%h latency=%0d expected=%0d",
                        index, expected_op[index], response.result, expected_result[index],
                        cycles-issued_cycle[index], expected_latency[index]);
                if (index > committed && !completion_seen[committed]) younger_first++;
                completion_seen[index] = 1;
            end
        end
    endtask

    always @(posedge clk) begin
        if (!rst_n) begin
            if (commit.valid !== 0 || ins_ready !== 0)
                $fatal(1, "handshake or commit active during reset");
        end else begin
            cycles++;
            if (cycles > 3000) $fatal(1, "timeout: fetched=%0d issued=%0d committed=%0d", fetched, issued, committed);
            if (stalled_last_cycle && (ins_valid !== 1 || ins !== stalled_ins))
                $fatal(1, "mock fetcher changed a stalled request");
            stalled_last_cycle = ins_valid && !ins_ready;
            if (stalled_last_cycle) begin
                stalled_ins = ins;
                fetch_stalls++;
            end
            if (!ins_valid && fetched < main_length) source_bubbles++;
            if (model_buf_valid) begin
                if (!dut.rs1_ready || !dut.rs2_ready || !dut.rs3_ready) raw_stalls++;
                if (!dut.rd_ready) waw_stalls++;
                if (issued == mul_consumer_index && !dut.rs1_ready) mul_raw_stalls++;
                if (issued == mul_waw_index && !dut.rd_ready) mul_waw_stalls++;
                if (!dut.alloc_ready) full_stalls++;
            end
            if (observed_issue.valid) begin
                if (dut.exec_valid !== 1 || dut.exec_ready !== 1 ||
                    dut.alloc_valid !== 1 || dut.alloc_ready !== 1)
                    $fatal(1, "issue/execute/allocate events differ");
                if (observed_issue.slot_addr !== COMMIT_SLOT_ADDR_W'(issued))
                    $fatal(1, "slot allocation sequence at issue %0d", issued);
                if (issued >= fetched) $fatal(1, "issued without a buffered instruction");
                if (model_pending[dut.rs1_addr] || model_pending[dut.rs2_addr] ||
                    model_pending[dut.rs3_addr]) forwarded++;
                if (issued > 0 && observed_issue.slot_addr == 0) wraps++;
                if (COMMIT_SLOT_NUM == 8 && issued > mul_stream_start && issued <= mul_stream_end
                    && cycles - issued_cycle[issued-1] != 1)
                    $fatal(1, "independent multiply stream did not issue every cycle");
                slot_instruction[observed_issue.slot_addr] = issued;
                issued_cycle[issued] = cycles;
                issued++;
            end
            if (observed_c1.valid && observed_c3.valid) begin
                if (observed_c1.slot_addr == observed_c3.slot_addr)
                    $fatal(1, "two completions target the same slot");
                multi_complete++;
            end
            check_completion(observed_c1);
            check_completion(observed_c3);
            if (commit.valid) begin
                if (committed >= issued) $fatal(1, "commit without issue");
                if (!completion_seen[committed]) $fatal(1, "commit before completion");
                if (commit.rd !== expected_rd[committed] ||
                    commit.result !== expected_result[committed])
                    $fatal(1, "commit %0d: r%0d=%h expected r%0d=%h", committed,
                        commit.rd, commit.result, expected_rd[committed], expected_result[committed]);
                committed++;
                model_pending[commit.rd] = 0;
            end
            if (issued - committed > COMMIT_SLOT_NUM - 1)
                $fatal(1, "queue capacity exceeded");
            if (observed_issue.valid && observed_issue.rd != 0)
                model_pending[observed_issue.rd] = 1;
            if (observed_issue.valid) model_buf_valid = 0;
            // Update at the end of this edge, so the DUT samples the old ROM entry.
            if (ins_valid && ins_ready) begin
                fetched <= fetched + 1;
                model_buf_valid = 1;
            end
        end
    end

    initial begin
        if (!$value$plusargs("WAVE_PATH=%s", wave_path))
            wave_path = "/workspace/build/cucpu-check/cucpu.vcd";
        $dumpfile(wave_path);
        $dumpvars(0, cucpu_tb);
        for (int r = 0; r < REG_NUM; r++) begin
            model_rf[r] = 0;
            model_pending[r] = 0;
        end
        for (int slot = 0; slot < COMMIT_SLOT_NUM; slot++) slot_instruction[slot] = -1;
        operations[0] = ALU_OP_INC; operations[1] = ALU_OP_DEC;
        operations[2] = ALU_OP_IADD; operations[3] = ALU_OP_ISUB;
        operations[4] = ALU_OP_AND; operations[5] = ALU_OP_OR;
        operations[6] = ALU_OP_XOR; operations[7] = ALU_OP_NOT;
        operations[8] = ALU_OP_SEL; operations[9] = ALU_OP_SHL;
        operations[10] = ALU_OP_SHR; operations[11] = ALU_OP_ILT;
        operations[12] = ALU_OP_ILE; operations[13] = ALU_OP_IGT;
        operations[14] = ALU_OP_IGE; operations[15] = ALU_OP_IEQ;
        operations[16] = ALU_OP_INE;
        operations[17] = ALU_OP_IMUL_LO; operations[18] = ALU_OP_IMUL_HI;

        // Immediate setup, RAW chains, WAW, r0 discard, signed shift and SEL.
        append_instruction(ALU_OP_IADD, 1, 0, 0, 0, 2, 7);
        append_instruction(ALU_OP_IADD, 2, 0, 0, 0, 1, 32'h80000005);
        append_instruction(ALU_OP_IADD, 3, 1, 2, 0);
        append_instruction(ALU_OP_INC, 3, 3, 0, 0);
        append_instruction(ALU_OP_SHL, 4, 3, 0, 0, 2, 2);
        append_instruction(ALU_OP_SHR, 5, 2, 0, 0, 2, 4, 1);
        append_instruction(ALU_OP_SHR, 6, 2, 0, 0, 2, 4, 0);
        append_instruction(ALU_OP_ILT, 7, 2, 1, 0, 0, 0, 1);
        append_instruction(ALU_OP_SEL, 8, 7, 1, 2);
        append_instruction(ALU_OP_SEL, 9, 7, 1, 0, 3, 32'hdeadbeef);
        append_instruction(ALU_OP_IADD, 0, 0, 0, 0, 2, 32'hffffffff);
        append_instruction(ALU_OP_IADD, 10, 0, 0, 0);
        append_instruction(ALU_OP_IMUL_LO, 11, 1, 2, 0);
        mul_consumer_index = length;
        append_instruction(ALU_OP_IADD, 12, 11, 1, 0);
        append_instruction(ALU_OP_IMUL_LO, 13, 1, 2, 0);
        mul_waw_index = length;
        append_instruction(ALU_OP_IADD, 13, 0, 0, 0, 2, 5);
        // Two independent adds after a multiply: younger completion first,
        // followed by latency-1 and latency-3 completing together.
        append_instruction(ALU_OP_IMUL_LO, 14, 1, 2, 0);
        append_instruction(ALU_OP_IADD, 15, 0, 0, 0, 2, 123);
        append_instruction(ALU_OP_IADD, 16, 0, 0, 0, 2, 456);
        append_instruction(ALU_OP_IMUL_HI, 17, 2, 0, 0, 2, 32'hffffffff);
        append_instruction(ALU_OP_IMUL_LO, 18, 2, 0, 0, 2, 32'hffffffff);
        mul_stream_start = length;
        for (int n = 0; n < 16; n++) begin
            if (n % 2)
                append_instruction(ALU_OP_IMUL_HI, 20 + n % 12, 2, 0, 0, 2, 32'hffffffff - n);
            else
                append_instruction(ALU_OP_IMUL_LO, 20 + n % 12, 2, 0, 0, 2, 32'hffffffff - n);
        end
        mul_stream_end = length - 1;
        // Every implemented operation occurs, with both modifier modes.
        for (int mode = 0; mode < 2; mode++)
            for (int op = 0; op < 19; op++)
                append_instruction(operations[op], 11 + op % 16, 2, 1, 8, 0, 0, mode);
        for (int n = 0; n < 160; n++) begin
            random_value = $random(seed);
            append_instruction(operations[random_value % 19],
                random_value[9:5], random_value[14:10], random_value[19:15], random_value[24:20],
                random_value[26:25], 32'h9e3779b9 ^ (random_value * 32'h45d9f3b), random_value[27]);
        end
        main_length = length;
        // After draining, read every register through RF, committing results to r0.
        for (int r = 0; r < REG_NUM; r++)
            append_instruction(ALU_OP_IADD, 0, REG_ADDR_W'(r), 0, 0);

        repeat (3) @(negedge clk);
        rst_n = 1;
        wait (committed == length);
        @(negedge clk);
        if (fetched != length || issued != length || fetch_stalls == 0 ||
            raw_stalls == 0 || waw_stalls == 0 || forwarded == 0 || wraps == 0 || source_bubbles == 0 ||
            multi_complete == 0 || younger_first == 0 || mul_raw_stalls == 0 || mul_waw_stalls == 0 ||
            (COMMIT_SLOT_NUM <= 4 && full_stalls == 0))
            $fatal(1, "missing protocol/coverage event");
        repeat (5) begin
            @(posedge clk); #1;
            if (commit.valid !== 0) $fatal(1, "extra commit after drain");
        end
        $display("PASS: %0d in-order ALU commits including 32 RF readbacks, %0d cycles", committed, cycles);
        $display("PASS: fetch stalls=%0d RAW=%0d WAW=%0d forwarding=%0d slot wraps=%0d source bubbles=%0d",
            fetch_stalls, raw_stalls, waw_stalls, forwarded, wraps, source_bubbles);
        $display("PASS: multiply RAW=%0d WAW=%0d simultaneous completes=%0d younger-first=%0d full stalls=%0d slots=%0d",
            mul_raw_stalls, mul_waw_stalls, multi_complete, younger_first, full_stalls, COMMIT_SLOT_NUM);
        $finish;
    end
endmodule
