create_clock -name {sys_clk_50m} -period 20.000 -waveform {0.000 10.000} [get_ports {I_sys_clk}]
create_clock -name {mipi_rx_ck_pad} -period 2.415 -waveform {0.000 1.208} [get_nets {IO_rx_clk_pad_p}]

derive_clocks

rename_clock -name {pll_clk_100m} [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[0]}]
rename_clock -name {pll_clk_24m} [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[1]}]
rename_clock -name {HDMI_PIXEL_CLK} [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[4]}]
rename_clock -name {HDMI_SERIAL_CLK} [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[5]}]

rename_clock -name {MIPI_RX_BYTE_CLK} [get_clocks {u_mipi_dphy_rx_ph1p_mipiio_wrapper/u_ph1p_mipiio_rx_wrapper/u_PH1P_LOGIC_DPHY_MIPI_RX.o_fabric_div4_8_clk}]

# SC520 顶层 CLK_DIV = 23809524/100000-1 = 237，scl_clk 每 119 个父钟周期翻转一次，
# 完整周期为 238 个父钟周期。父钟实际频率 23.809524 MHz。
create_generated_clock -name {I2C_SCL_CLK} \
    -source [get_pins {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[1]}] \
    -master_clock {pll_clk_24m} -divide_by 238 \
    [get_nets {u_uicfgcs520/u_i2c/scl_clk}]

# 保留原有无关域隔离，仅开放两对 FIFO 跨时钟域关系（DDR 用户域 ↔ MIPI 字节域、DDR 用户域 ↔ HDMI 像素域）。
set_clock_groups -asynchronous \
    -group [get_clocks {mipi_rx_ck_pad MIPI_RX_BYTE_CLK}] \
    -group [get_clocks {sys_clk_50m pll_clk_100m pll_clk_24m I2C_SCL_CLK HDMI_SERIAL_CLK}]
# Keep the pad clock isolated; byte-clock <-> pixel-clock now has explicit CDC endpoints.
set_clock_groups -asynchronous \
    -group [get_clocks {mipi_rx_ck_pad}] \
    -group [get_clocks {HDMI_PIXEL_CLK}]
set_clock_groups -asynchronous \
    -group [get_clocks {u_ph1p35_324_ddr_wrapper/u_ddr2/ddr_clk}] \
    -group [get_clocks {mipi_rx_ck_pad MIPI_RX_BYTE_CLK sys_clk_50m pll_clk_100m pll_clk_24m I2C_SCL_CLK HDMI_PIXEL_CLK HDMI_SERIAL_CLK}]
set_clock_groups -asynchronous \
    -group [get_clocks {u_ph1p35_324_ddr_wrapper/u_ddr2/usr_clk}] \
    -group [get_clocks {mipi_rx_ck_pad sys_clk_50m pll_clk_100m pll_clk_24m I2C_SCL_CLK HDMI_SERIAL_CLK}]
# SWUG200 5.3.2：只为这些异步 FIFO/帧控路径设定物理上限。
# IP 内部灰码 max_delay 更严格；同域第二级同步仍正常 STA。
# 100 ns 是宽松物理上限，不是同步采样预算。
set_max_delay -from [get_clocks {MIPI_RX_BYTE_CLK}] -to [get_clocks {u_ph1p35_324_ddr_wrapper/u_ddr2/usr_clk}] -datapath_only 100
set_max_delay -from [get_clocks {u_ph1p35_324_ddr_wrapper/u_ddr2/usr_clk}] -to [get_clocks {MIPI_RX_BYTE_CLK}] -datapath_only 100
set_max_delay -from [get_clocks {HDMI_PIXEL_CLK}] -to [get_clocks {u_ph1p35_324_ddr_wrapper/u_ddr2/usr_clk}] -datapath_only 100
set_max_delay -from [get_clocks {u_ph1p35_324_ddr_wrapper/u_ddr2/usr_clk}] -to [get_clocks {HDMI_PIXEL_CLK}] -datapath_only 100

# PQ publishes complete frame-held payloads in the pixel domain. Bound the
# bundled-data arrival independently of phase; do not exempt the payload bus.
# The event has three stages, the payload two; 20 ns < one 24 MHz period.
set_max_delay -datapath_only 20.000 -from [get_regs {u_video_display_pipe/u_ae_stats/stats_sum[*]}] -to [get_regs {u_ae_ctrl/ssum_1[*]}]
# Exempt only asynchronous arrival at the scalar event's first stage.
set_false_path -from [get_clocks {HDMI_PIXEL_CLK}] -to [get_regs {u_ae_ctrl/tgl_1}]
# P5 (frame latency): frame_meta publishes a frame-held payload (latency + validity, DDR/user
# domain) with a single-bit event toggle. hdmi_mixer samples it in the pixel domain with four
# event stages and two payload stages, exactly like the PQ path above: bound the bundled-data
# arrival into the payload's FIRST stage and exempt only the asynchronous arrival at the event
# bit's first stage (later stages stay timed).
# First samplers stay at module scope for simple logical names. The earlier generate-scope
# attempts used incorrect synthesized names and failed with USR-6001/USR-8159. get_regs uses
# logical register names (a later-stage example is g_lat$lat_tgl_2). A bare suffix wildcard also
# collects the driving source
# registers in TD (measured: lat_vld_1* includes frame_meta/o_lat_valid), which would relax
# producer-domain timing. Bus brackets and exact scalar names select only the first samplers.
set_max_delay -datapath_only 20.000 -from [get_clocks {u_ph1p35_324_ddr_wrapper/u_ddr2/usr_clk}] -to [get_regs {u_hdmi_mixer/lat_ms_1[*] u_hdmi_mixer/lat_vld_1}]
set_false_path -from [get_clocks {u_ph1p35_324_ddr_wrapper/u_ddr2/usr_clk}] -to [get_regs {u_hdmi_mixer/lat_tgl_1}]
# Reverse direction: the first-output-pixel event is sampled by frame_meta's first stage.
set_false_path -from [get_clocks {HDMI_PIXEL_CLK}] -to [get_regs {u_frame_meta/ot1}]
# Sticky read underflow is a single pixel-domain level; only its first sampler is exempt.
set_false_path -from [get_clocks {HDMI_PIXEL_CLK}] -to [get_regs {u_frame_meta/uf1}]
# Frame-head reset acknowledgement and sticky capture loss use scalar two/three-stage samplers.
set_false_path -from [get_clocks {u_ph1p35_324_ddr_wrapper/u_ddr2/usr_clk}] -to [get_regs {u_video_in/head_rst1}]
set_false_path -from [get_clocks {MIPI_RX_BYTE_CLK}] -to [get_regs {u_frame_meta/cf1}]

# SW1 asynchronous input: only the first pixel-clock synchronizer stage.
set_false_path -from [get_ports {I_denoise_sw}] -to [get_regs {u_denoise_switch/sync1}]

set_false_path -from [get_ports {I_exposure_lock_sw}] -to [get_regs {u_lock_switch/sync1}]

set_false_path -from [get_ports {I_awb_freeze_sw}] -to [get_regs {u_wb_switch/sync1}]

set_false_path -from [get_ports {I_calibration_sw}] -to [get_regs {u_cal_switch/sync1}]

set_false_path -from [get_clocks {HDMI_PIXEL_CLK}] -to [get_regs {u_ae_ctrl/hold_1}]
set_max_delay -datapath_only 20.000 -from [get_clocks {HDMI_PIXEL_CLK}] -to [get_regs {u_ae_ctrl/clip_1[*]}]

# AWB diagnostic packet is held until acknowledgement. Event uses three stages;
# bound the first bundled-data sampler to less than one HDMI pixel period.
set_max_delay -datapath_only 10.000 -from [get_regs {u_awb_status_cdc/held[*]}] -to [get_regs {u_awb_status_cdc/data_1[*]}]
set_false_path -from [get_clocks {MIPI_RX_BYTE_CLK}] -to [get_regs {u_awb_status_cdc/req_1}]
set_false_path -from [get_clocks {HDMI_PIXEL_CLK}] -to [get_regs {u_awb_status_cdc/ack_1}]
set_max_delay -datapath_only 20.000 -from [get_regs {u_video_display_pipe/u_ae_stats/stats_local_high[*]}] -to [get_regs {u_ae_ctrl/local_1[*]}]

# Existing WB level handshakes: exempt first synchronizer only; later stages are timed.
set_false_path -from [get_clocks {HDMI_PIXEL_CLK}] -to [get_regs {u_isp_top/u_awb/f1}]
set_false_path -from [get_clocks {MIPI_RX_BYTE_CLK}] -to [get_regs {u_hdmi_mixer/wb_frozen_1}]
