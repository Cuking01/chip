# 顺序 ALU 指令流仿真

运行 `make check-cucpu`。测试入口是 `tests/cucpu_tb.sv`，脚本为 `scripts/check_cucpu.sh`。

当前 `cucpu` 顶层通过 `ins`、`ins_valid`、`ins_ready` 接收外部指令流，并输出 `commit_t commit` 供观察。正式 fetcher 仍是占位实现；其 `pc_rst` 不影响本测试的指令流。测试里的模拟 fetcher 使用指令 ROM，仅在上升沿握手成功时推进，阻塞时保持指令及 valid。

顶层已连接 issuer、executor_alu、commit_queue 和 operand_resolver（含 RF）。发射时同步分配提交槽并登记依赖，执行结果通过 complete 写入槽位，队头完成后按序提交；同一个 commit 事件完成 RF 写入和依赖解除。

测试包含 206 条程序指令及 32 条 RF 读回指令，覆盖所有已实现的 17 种 ALU 操作、两种符号修饰模式、三种立即数位置、RAW、WAW、forwarding、写 r0、输入空泡和槽号回绕。独立软件模型按程序顺序计算结果，逐项核对提交的 rd/result。程序全部提交后，以 `IADD r0, rN, r0` 读回每个寄存器，验证实际 RF 内容；这些读回结果仍输出到 commit，但 RF 丢弃对 r0 的写入。

脚本先转换工作区的花括号语法，再通过 slang/Yosys 将整个 CPU RTL 降为 Verilog 并检查结构，最后用 Icarus 运行 SV 测试。该流程支持提交队列中动态下标访问结构体数组。日志、生成的 Verilog 和波形保存在 `build/cucpu-check/`，波形文件为 `cucpu.vcd`。

目前未验证乘法、多周期混合完成、除法、访存或控制流；测试仅发送已实现的 ALU 指令。单周期执行时队列不一定会满，本测试的回绕检查不等同于满队列压力测试。
