package cucpu_common;
    localparam integer DW = 32;             // 数据宽度
    localparam integer IW = 64;             // 指令宽度
    localparam integer ADDR_W = 32;         // 地址线宽度
    localparam integer OP_GROUP_W = 2;      // 指令组描述宽度
    localparam integer OP_CODE_W = 6;       // 指令码宽度
    localparam integer REG_NUM = 32;        // 寄存器数
    localparam integer REG_ADDR_W = 5;      // 寄存器号宽度
    localparam integer ALU_MODIFIER_W = 7;  // ALU 指令修饰符位宽
    localparam integer ALU_MOD_SIGNED_BIT = 0; // 比较及右移：0 为无符号，1 为有符号。
    localparam integer COMMIT_SLOT_NUM = 8;    // commit队列大小，负责 forwarding 和写回，必须是2的幂次，实际可用大小需要减1，不能全部用满
    localparam integer COMMIT_SLOT_ADDR_W = 3; // commit队列槽地址宽度

    typedef struct packed {
        reg done;
        reg [REG_ADDR_W-1:0] rd;
        reg [DW-1:0] res;
    } commit_slot;

    // 执行单元返回的完成信息；槽号对应发射时分配的提交槽。
    typedef struct packed {
        logic valid;
        logic [COMMIT_SLOT_ADDR_W-1:0] slot_addr;
        logic [DW-1:0] result;
    } complete_t;

    // 真正成功发射后，通知依赖管理逻辑建立生产者记录。
    typedef struct packed {
        logic valid;
        logic [REG_ADDR_W-1:0] rd;
        logic [COMMIT_SLOT_ADDR_W-1:0] slot_addr;
    } issue_t;

    // 正式提交时，写入 RF 并通知依赖管理逻辑解除对应依赖。
    typedef struct packed {
        logic valid; // 同时作为 RF 写使能和解除依赖使能；复位期间为 0。
        logic [REG_ADDR_W-1:0] rd; // 写回及解除依赖的目标寄存器。
        logic [DW-1:0] result; // 写回 RF 的数据。
    } commit_t;

    typedef enum logic [OP_GROUP_W-1:0] {
        OP_GROUP_ALU=2'b0,
        OP_GROUP_MEM,
        OP_GROUP_CONTROL,
        OP_GROUP_OTHER
    } op_group_t;

    // 原始 ALU 指令的 payload，字段顺序与 ISA 的 [55:0] 对应。
    typedef struct packed {
        logic [6:0]  modifiers;
        logic [4:0]  rd;
        logic [4:0]  rs1;
        logic [4:0]  rs2;
        logic [4:0]  rs3;
        logic [1:0]  imm_sel;
        logic [26:0] imm;
    } alu_payload_t;

    // 所有视图共用 56 bit；访存、控制流格式确定后替换对应占位成员。
    typedef union packed {
        alu_payload_t alu;
        logic [55:0] memory;
        logic [55:0] control;
        logic [55:0] raw;
    } instr_payload_t;

    typedef struct packed {
        op_group_t op_group;
        logic [5:0] op_code;
        instr_payload_t payload;
    } instr_t;



    // ALU 内部操作码，按声明顺序从 0 自动递增。
    // 位宽由 OP_CODE_W 统一定义。
    typedef enum logic [OP_CODE_W-1:0] {
        ALU_OP_INC = 6'd0,
        ALU_OP_DEC,
        ALU_OP_IADD,
        ALU_OP_ISUB,
        ALU_OP_IMUL_LO,
        ALU_OP_IMUL_HI,
        ALU_OP_IMAD_LO,
        ALU_OP_IMAD_HI,
        ALU_OP_IADD3,

        ALU_OP_AND,
        ALU_OP_OR,
        ALU_OP_XOR,
        ALU_OP_NOT,

        ALU_OP_SHL,
        ALU_OP_SHR,

        ALU_OP_SEL, // 根据 rs1，逐位选择：0 选 rs2，1 选 rs3。

        // 比较成立，结果纯1，相当于有符号的负一，否则为0
        ALU_OP_ILT, // 小于
        ALU_OP_ILE, // 小于等于
        ALU_OP_IGT, //大于
        ALU_OP_IGE, //大于等于
        ALU_OP_IEQ, //等于
        ALU_OP_INE  //不等于

    } alu_op_t;

    function automatic integer op_latency(input alu_op_t op);
        case (op)
            ALU_OP_INC,
            ALU_OP_DEC,
            ALU_OP_IADD,
            ALU_OP_ISUB,
            ALU_OP_AND,
            ALU_OP_OR,
            ALU_OP_XOR,
            ALU_OP_NOT,
            ALU_OP_SHL,
            ALU_OP_SHR,
            ALU_OP_SEL,
            ALU_OP_ILT,
            ALU_OP_ILE,
            ALU_OP_IGT,
            ALU_OP_IGE,
            ALU_OP_IEQ,
            ALU_OP_INE:
                op_latency = 1;

            ALU_OP_IADD3:
                op_latency = 2;

            ALU_OP_IMUL_LO,
            ALU_OP_IMUL_HI:
                op_latency = 3;

            ALU_OP_IMAD_LO,
            ALU_OP_IMAD_HI:
                op_latency = 4;

            default:
                op_latency = 0; // 暂未支持或非法操作
        endcase
    endfunction


endpackage
