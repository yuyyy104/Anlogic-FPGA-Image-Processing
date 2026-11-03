# 工程复现说明

## 环境准备

硬件使用 HX1P35A 开发板、SC520CS 摄像头、匹配的 FPC 转接线、HDMI 显示器及板卡下载连接。断电连接摄像头，核对排线方向后上电。

软件使用 TangDynasty 6.2、Python 3.9 或以上；模块仿真使用 ModelSim。工程器件为 PH1P35MDG324、Speed Grade 3，顶层为 `design_top_wrapper`。

## 本机路径配置

在克隆后的工程根目录执行：

```powershell
python prepare_project.py --td-home D:/TD_6.2.1
```

将 `--td-home` 替换为实际 TD 根目录。脚本替换归档工程中的旧绝对路径，校验 TD 工程列出的输入文件，并按压缩清单恢复 238 个仿真 `.mem` 输入。恢复时逐项检查 SHA-256，不覆盖内容不同的本地输入。

路径配置会改变工作副本中的路径字符串，并生成 `.local_paths.json`；该文件不纳入版本控制。发布校验清单针对克隆后、配置前的文件。

## 综合、布局布线与下载

TD 图形界面打开：

```text
prj/td/lab_ex3_sc520/td_project/camera_to_dsi_display.al
```

也可使用命令行，以下路径按实际安装和克隆位置替换：

```powershell
& 'D:/TD_6.2.1/bin/td_commands_prompt.exe' 'D:/work/Anlogic-FPGA-Image-Processing/prj/scripts/build_td_sc520.tcl'
```

构建脚本依次执行综合、布局布线和约束检查，并检查生成的 bit 是否为当前构建产物。新构建结果位于工程的 `camera_to_dsi_display_Runs/phy_1/`，应同时检查该次资源与时序报告。

`bit/` 保存对应归档构建的普通位流与压缩位流。通过板卡适配的下载工具载入普通位流，检查 HDMI 彩色画面、模式切换、阈值调节、红黄绿目标及曝光/白平衡状态。

## 工程约束与完整输入

工程包含引脚/物理约束 `.adc`、时序约束 `.sdc`、RTL `.v` / `.sv`、平台 IP、初始化数据、工程配置及仿真支持文件。复现时保留目录结构。FPGA 平台与 DDR 子系统各有约束文件，由工程配置引用。

本平台采用安路 TD 的 ADC/SDC 约束体系；以 `.al` 工程实际引用关系为准。

## 模块仿真

完成路径和输入恢复后，在 ModelSim 可执行文件所在目录已加入 PATH 的环境中执行：

```powershell
vsim -c -do 'source prj/scripts/sim_btn_ctrl.tcl'
vsim -c -do 'source prj/scripts/sim_shared_denoise.tcl'
vsim -c -do 'source prj/scripts/sim_color_matrix.tcl'
```

使用 Tcl `source` 载入脚本，使脚本可通过 `info script` 定位工程根目录。脚本检查测试完成标志与错误数，失败返回非零退出状态。仿真输出写入 `tmp/`。共享降噪脚本默认使用随工程提供的 ERAM 行为模型；器件库验收应使用对应 TD 版本的厂商模型，行为仿真结果不能替代器件实现与实板测试。

## 板上验证顺序

1. 检查摄像头接入、HDMI 连续输出和 OSD 状态。
2. 按 KEY1 检查六种模式，按 KEY2 检查二值化阈值变化。
3. 在稳定照明下分别放置红、黄、绿目标，检查颜色信息与目标框。
4. 检查 SW1 降噪、SW2 曝光锁定、SW3 白平衡冻结、SW4 九点观测。
5. 保持机位、距离与目标一致，记录各照明条件及帧级统计，形成可比较的应用验证结果。
