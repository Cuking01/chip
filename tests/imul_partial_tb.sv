module imul_partial_tb;
    import cucpu_common::*;

    logic clk = 0, rst_n = 0, valid0 = 0;
    logic [DW-1:0] a = 0, b = 0;
    logic [COMMIT_SLOT_ADDR_W-1:0] slot_addr0 = 0;
    logic high_half = 0, previous_high_half = 0;
    complete_t complete;
    logic [DW-1:0] corners [0:8];
    logic [DW*2-1:0] previous_product;
    logic previous_valid = 0, previous_known = 0;
    logic [COMMIT_SLOT_ADDR_W-1:0] previous_slot = 0;
    integer checks = 0, seed = 32'h12345678;
    logic [DW*2-1:0] add_a = 0, add_b = 0, add_result;
    logic add_carry_in = 0, half_carry;
    logic [DW-1:0] half_result;
    logic [DW*2-1:0] add_corners [0:8];
    integer adder_checks = 0;

    imul_add_helper adder(.a(add_a), .b(add_b), .c(add_result));
    imul_add_helper_half half_adder(.a(add_a[DW-1:0]), .b(add_b[DW-1:0]),
        .carry_in(add_carry_in), .c(half_result), .carry_out(half_carry));

    always #5 clk = ~clk;
    imul dut(.clk, .rst_n, .valid0, .rs1(a), .rs2(b),
        .signed_mode(1'b0), .high_half, .slot_addr0, .complete);

    task automatic check_adders(
        input logic [DW*2-1:0] x, y, input logic cin
    );
        logic [DW:0] expected_half;
        logic [DW*2-1:0] expected_full;
        begin
            expected_half = {1'b0,x[DW-1:0]} + {1'b0,y[DW-1:0]} + cin;
            expected_full = x + y;
            add_a = x; add_b = y; add_carry_in = cin;
            #1;
            if ({half_carry,half_result} !== expected_half || add_result !== expected_full)
                $fatal(1, "carry-select a=%h b=%h cin=%b half=%h expected=%h full=%h expected=%h",
                    x, y, cin, {half_carry,half_result}, expected_half, add_result, expected_full);
            adder_checks++;
        end
    endtask

    // Check every compression layer and the final selected product half.
    task automatic tick(input logic [DW-1:0] x, y,
        input logic request_valid = 1, input logic select_high = 0);
        logic [DW*2-1:0] expected, s0, s1, s2, s3, s4, s5, s6;
        logic [COMMIT_SLOT_ADDR_W-1:0] expected_slot;
        begin
            expected = {{DW{1'b0}}, x} * {{DW{1'b0}}, y};
            expected_slot = COMMIT_SLOT_ADDR_W'(checks);
            @(negedge clk);
            a = x; b = y; valid0 = request_valid; slot_addr0 = expected_slot;
            high_half = select_high;
            @(posedge clk); #1;
            s0 = 0; s1 = 0; s2 = 0; s3 = 0; s4 = 0; s5 = 0; s6 = 0;
            for (int i = 0; i < 17; i++) s0 += dut.partial[i];
            for (int i = 0; i < 12; i++) s1 += dut.partial1[i];
            for (int i = 0; i < 8; i++) s2 += dut.partial2[i];
            for (int i = 0; i < 6; i++) s3 += dut.partial3[i];
            for (int i = 0; i < 4; i++) s4 += dut.partial4[i];
            for (int i = 0; i < 3; i++) s5 += dut.partial5[i];
            for (int i = 0; i < 2; i++) s6 += dut.partial6[i];
            if (s0 !== expected || s1 !== expected || s2 !== expected ||
                s3 !== expected || s4 !== expected)
                $fatal(1, "stage1 a=%h b=%h expected=%h sums=%h/%h/%h/%h/%h",
                    x, y, expected, s0, s1, s2, s3, s4);
            if (previous_known && (s5 !== previous_product || s6 !== previous_product))
                $fatal(1, "stage2 expected=%h sums=%h/%h", previous_product, s5, s6);
            if (complete.valid !== previous_valid ||
                (previous_valid && complete.slot_addr !== previous_slot))
                $fatal(1, "valid/slot pipeline mismatch");
            if (previous_valid && complete.result !== (previous_high_half
                ? previous_product[DW*2-1:DW] : previous_product[DW-1:0]))
                $fatal(1, "final product half mismatch");
            previous_product = expected;
            previous_valid = request_valid;
            previous_slot = expected_slot;
            previous_high_half = high_half;
            previous_known = 1;
            checks++;
        end
    endtask

    initial begin
        corners[0] = 0; corners[1] = 1; corners[2] = 2;
        corners[3] = 7; corners[4] = 14; corners[5] = 32'h7fffffff;
        corners[6] = 32'h80000000; corners[7] = 32'hffffffff;
        corners[8] = 32'haaaaaaaa;
        add_corners[0] = 0; add_corners[1] = 1;
        add_corners[2] = 64'hffff; add_corners[3] = 64'h10000;
        add_corners[4] = 64'hffffffff; add_corners[5] = 64'h100000000;
        add_corners[6] = 64'h8000000000000000;
        add_corners[7] = 64'h7fffffffffffffff;
        add_corners[8] = 64'hffffffffffffffff;
        for (int x = 0; x < 9; x++)
            for (int y = 0; y < 9; y++)
                for (int cin = 0; cin < 2; cin++)
                    check_adders(add_corners[x], add_corners[y], cin);
        repeat (1000)
            check_adders({$random(seed),$random(seed)}, {$random(seed),$random(seed)}, $random(seed));
        repeat (2) @(negedge clk);
        rst_n = 1;
        for (int x = 0; x < 9; x++)
            for (int y = 0; y < 9; y++) begin
                tick(corners[x], corners[y], 1, 0);
                tick(corners[x], corners[y], 1, 1);
            end
        for (int n = 0; n < 1000; n++) tick($random(seed), $random(seed), n % 7 != 0, n % 2);
        // Reset with a valid request still in flight, then restart.
        tick(32'hffffffff, 32'hffffffff);
        @(negedge clk); rst_n = 0; valid0 = 0;
        @(posedge clk); #1;
        if (complete.valid !== 0) $fatal(1, "reset did not flush valid");
        previous_valid = 0; previous_known = 0;
        @(negedge clk); rst_n = 1;
        tick(32'h80000000, 3);
        tick(9, 14);
        tick(0, 0, 0);
        tick(0, 0, 0);
        if (complete.valid !== 0) $fatal(1, "bubble did not drain valid");
        $display("PASS: %0d unsigned Booth/CSA checks across all 7 arrays, slots, bubbles and reset", checks);
        $display("PASS: %0d carry-select adder checks including both carry inputs, 16/32-bit carries and overflow", adder_checks);
        $finish;
    end
endmodule
