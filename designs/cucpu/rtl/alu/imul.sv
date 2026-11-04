

module imul_add_helper_half
    import cucpu_common::*;
(
    input logic[DW-1:0] a,
    input logic[DW-1:0] b,
    input logic carry_in,
    output logic[DW-1:0] c,
    output logic carry_out
);
    logic low_carry;
    // 高半候选值额外保留一位，将最终 carry_out 一起选择。
    logic [DW/2:0] high0_res,high1_res;

    assign {low_carry,c[DW/2-1:0]} =
        {1'b0,a[DW/2-1:0]} + {1'b0,b[DW/2-1:0]} + carry_in;
    assign high0_res = {1'b0,a[DW-1:DW/2]} + {1'b0,b[DW-1:DW/2]};
    assign high1_res = {1'b0,a[DW-1:DW/2]} + {1'b0,b[DW-1:DW/2]} + 1'b1;
    assign {carry_out,c[DW-1:DW/2]} = low_carry ? high1_res : high0_res;
endmodule

module imul_add_helper
    import cucpu_common::*;
(
    input logic[2*DW-1:0] a,
    input logic[2*DW-1:0] b,
    output logic[2*DW-1:0] c
);
    logic carry_out;
    imul_add_helper_half low(.a(a[DW-1:0]),.b(b[DW-1:0]),.carry_in(1'b0),.c(c[DW-1:0]),.carry_out);
    logic [DW-1:0] high0_res,high1_res;
    imul_add_helper_half high0(.a(a[2*DW-1:DW]),.b(b[2*DW-1:DW]),.carry_in(1'b0),.c(high0_res),.carry_out());
    imul_add_helper_half high1(.a(a[2*DW-1:DW]),.b(b[2*DW-1:DW]),.carry_in(1'b1),.c(high1_res),.carry_out());
    assign c[DW*2-1:DW] = carry_out?high1_res:high0_res;
endmodule


module imul
    import cucpu_common::*;
(
    input logic clk,
    input logic rst_n,

    input logic valid0,
    input logic [DW-1:0] rs1,
    input logic [DW-1:0] rs2,
    input logic signed_mode, // 1：两个操作数均有符号；0：均无符号。
    input logic high_half, // 1：返回乘积高 DW 位；0：返回低 DW 位。
    input logic [COMMIT_SLOT_ADDR_W-1:0] slot_addr0,

    output complete_t complete
);
    function automatic logic [DW*2-1:0] csa_sum(
        input logic [DW*2-1:0] a, b, c
    );
        return a ^ b ^ c;
    endfunction

    function automatic logic [DW*2-1:0] csa_carry(
        input logic [DW*2-1:0] a, b, c
    );
        return ((a & b) | (a & c) | (b & c)) << 1;
    endfunction

    // 每层三行压为两行，未组成三行的输入直接传递。
    // 行数：17 -> 12 -> 8 -> 6 -> 4 -> 3 -> 2。
    logic[DW*2-1:0] partial[0:16];
    reg[DW*2-1:0] partial1[0:11];
    logic[DW*2-1:0] partial2[0:7];
    logic[DW*2-1:0] partial3[0:5];
    logic[DW*2-1:0] partial4[0:3];
    reg[DW*2-1:0] partial5[0:2];
    logic[DW*2-1:0] partial6[0:1];
    logic[DW*2-1:0] res;
    
    reg valid[1:2];
    reg[COMMIT_SLOT_ADDR_W-1:0] slot_addr[1:2];
    logic high_half_pipe[1:2];

    assign complete.valid=valid[2];
    assign complete.slot_addr=slot_addr[2];
    assign complete.result=high_half_pipe[2] ? res[DW*2-1:DW] : res[DW-1:0];

    imul_add_helper add_inst(.a(partial6[0]),.b(partial6[1]),.c(res));

    always_comb
    {
        //第一周期，算部分和和一层压缩，压缩计算放在always_ff里
        for(integer i=0;i<DW;i+=2)
        {
            logic[DW*2-1:0] tmp;
            logic[1:0] k;
            
            if(i>0)k = rs2[i+:2]+rs2[i-1];
            else k = rs2[i+:2];

            tmp = {{DW{1'b0}},rs1} ^ {(DW*2){rs2[i+1]}};

            case(k)
                0: tmp = '0;
                1,3: tmp = tmp << i;
                2: tmp = tmp << (i+1);
            endcase

            partial[i/2] = tmp;
            partial[16][i] = rs2[i+1]&k[0];
            partial[16][i+1] = rs2[i+1]&(k==2);
        }
        partial[16][DW*2-1:DW] = rs2[DW-1]?rs1:DW'(0);

        //第二周期，算四层压缩，最后一层也放always_ff里
        // partial1 的 12 行全部分为四组，压为 8 行。
        for(integer i=0;i<4;i++)
        {
            partial2[2*i] = csa_sum(partial1[3*i],partial1[3*i+1],partial1[3*i+2]);
            partial2[2*i+1] = csa_carry(partial1[3*i],partial1[3*i+1],partial1[3*i+2]);
        }

        // 8 -> 6：压缩两组，剩余两行直连。
        for(integer i=0;i<2;i++)
        {
            partial3[2*i] = csa_sum(partial2[3*i],partial2[3*i+1],partial2[3*i+2]);
            partial3[2*i+1] = csa_carry(partial2[3*i],partial2[3*i+1],partial2[3*i+2]);
        }
        partial3[4] = partial2[6];
        partial3[5] = partial2[7];

        // 6 -> 4：压缩两组。
        for(integer i=0;i<2;i++)
        {
            partial4[2*i] = csa_sum(partial3[3*i],partial3[3*i+1],partial3[3*i+2]);
            partial4[2*i+1] = csa_carry(partial3[3*i],partial3[3*i+1],partial3[3*i+2]);
        }

        // 第三周期，3 -> 2；后续对这两行做最终进位传播加法。
        partial6[0] = csa_sum(partial5[0],partial5[1],partial5[2]);
        partial6[1] = csa_carry(partial5[0],partial5[1],partial5[2]);

    }

    always_ff @(posedge clk)
    {
        if(!rst_n)
        {
            valid[1] <= '0;
            valid[2] <= '0;
            slot_addr[1] <= '0;
            slot_addr[2] <= '0;
            high_half_pipe[1] <= '0;
            high_half_pipe[2] <= '0;
        }
        else
        {
            valid[1] <= valid0;
            valid[2] <= valid[1];
            slot_addr[1] <= slot_addr0;
            slot_addr[2] <= slot_addr[1];
            high_half_pipe[1] <= high_half;
            high_half_pipe[2] <= high_half_pipe[1];
            
            for(integer i=0;i<5;i++)
            {
                partial1[2*i] <= csa_sum(partial[3*i],partial[3*i+1],partial[3*i+2]);
                partial1[2*i+1] <= csa_carry(partial[3*i],partial[3*i+1],partial[3*i+2]);
            }
            
            partial1[10] <= partial[15];
            partial1[11] <= partial[16];
            // 第二周期的最后一层：4 -> 3，并锁存结果。
            partial5[0] <= csa_sum(partial4[0],partial4[1],partial4[2]);
            partial5[1] <= csa_carry(partial4[0],partial4[1],partial4[2]);
            partial5[2] <= partial4[3];
        }
    }
endmodule
