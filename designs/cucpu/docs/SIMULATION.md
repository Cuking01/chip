# 顺序 ALU 指令流仿真

运行 `make check-cucpu`。测试入口是 `tests/cucpu_tb.sv`，脚本为 `scripts/check_cucpu.sh`。

当前 `cucpu` 顶层通过 `ins`、`ins_valid`、`ins_ready` 接收外部指令流，并输出 `commit_t commit` 供观察。正式 fetcher 仍是占位实现；其 `pc_rst` 不影响本测试的指令流。测试里的模拟 fetcher 使用指令 ROM，仅在上升沿握手成功时推进，阻塞时保持指令及 valid。

顶层已连接 issuer、executor_alu、commit_queue 和 operand_resolver（含 RF）。发射时同步分配提交槽并登记依赖，执行结果通过 complete 写入槽位，队头完成后按序提交；同一个 commit 事件完成 RF 写入和依赖解除。

测试包含 235 条程序指令及 32 条 RF 读回指令，覆盖所有已实现的 19 种 ALU 操作、比较与右移的两种符号修饰模式、三种立即数位置、RAW、WAW、forwarding、写 r0、输入空泡和槽号回绕。乘法仅验证无符号高低半结果。独立软件模型按程序顺序计算结果，逐项核对提交的 rd/result。程序全部提交后，以 `IADD r0, rN, r0` 读回每个寄存器，验证实际 RF 内容；这些读回结果仍输出到 commit，但 RF 丢弃对 r0 的写入。

乘法测试包括连续独立发射、紧邻的 RAW/WAW、年轻加法先完成，以及延迟 1 和延迟 3 同拍 complete。每路 complete 都按槽号核对结果、执行延迟和唯一性。若在上升沿 N 发射，单周期 complete 在 N+1 沿被队列接收，乘法 complete 在 N+3 沿被接收。完成可以乱序，提交仍必须逐条遵守程序顺序。

`make check-cucpu` 同时运行正常 8 槽配置和临时生成的 4 槽配置（实际可用 3 槽）。后者用于触发满队列阻塞，检查请求保持及释放后恢复，不修改源码里的队列容量。正常配置还检查连续独立乘法能每周期发射。

脚本先转换工作区的花括号语法，再通过 slang/Yosys 将整个 CPU RTL 降为 Verilog 并检查结构，最后用 Icarus 运行 SV 测试。该流程支持提交队列中动态下标访问结构体数组。正常配置的日志、生成的 Verilog 和波形保存在 `build/cucpu-check/`；小队列版本保存在 `build/cucpu-check-small-queue/`，波形文件均为 `cucpu.vcd`。

`make check-imul` 还独立验证 Booth 部分积、六层压缩、最终高低半选择、carry-select 加法器、valid/槽号流水、空泡和执行中复位。时序约束下的 ASIC 库映射和频率尚未验证。有符号乘法、除法、访存和控制流尚未实现。
