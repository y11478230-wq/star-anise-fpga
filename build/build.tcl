# PYNQ-Z1 OV5640 RGB565 -> VDMA -> 720p letterbox -> HDMI OUT.
# Usage: vivado -mode batch -source build_camera_hdmi_720p.tcl -tclargs bd|full
set script_dir [file dirname [file normalize [info script]]]
set root_dir [file dirname $script_dir]
if {[info exists ::env(STAR_ANISE_ENGINEERING_ROOT)]} {
    # Windows Vivado 2026.1 cannot open projects below this workspace's
    # non-ASCII folder name.  A caller may provide an ASCII junction path.
    set root_dir $::env(STAR_ANISE_ENGINEERING_ROOT)
    set script_dir [file join $root_dir scripts]
}
set workspace [file dirname [file dirname $root_dir]]
if {[info exists ::env(STAR_ANISE_WORKSPACE_ROOT)]} {
    set workspace $::env(STAR_ANISE_WORKSPACE_ROOT)
}
set project_dir [file join $root_dir vivado camera_hdmi_720p]
set delivery_dir [file join $workspace camera_hdmi_720p_delivery]
set overlay_dir [file join $workspace star_anise_fpga overlays]
set project_name camera_hdmi_720p_project
set design_name system
set build_stage [expr {[llength $argv] ? [lindex $argv 0] : "full"}]
set sixpanel_cnn [expr {$build_stage eq "cnn_live_sixpanel" || $build_stage eq "cnn_live_sixpanel_bd"}]
set python_sixpanel [expr {$build_stage eq "python_sixpanel" || $build_stage eq "python_sixpanel_bd"}]
set fpga_sixpanel [expr {$build_stage eq "fpga_sixpanel" || $build_stage eq "fpga_sixpanel_bd"}]
set shadow_compare [expr {$build_stage eq "cnn_live_shadow_compare" || $build_stage eq "cnn_live_shadow_compare_bd" || $sixpanel_cnn}]
set fpga_mask_compare [expr {$build_stage eq "fpga_mask_compare" || $build_stage eq "fpga_mask_compare_bd"}]
set cnn_image_process [expr {$build_stage eq "cnn_live_image_process" || $build_stage eq "cnn_live_image_process_bd" || $shadow_compare}]
set image_processing [expr {$build_stage eq "image_process" || $cnn_image_process}]
set raster_mux_test [expr {$build_stage eq "raster_mux_test"}]
set bram_live [expr {$build_stage eq "bram_live"}]
set cnn_cropmatch [expr {$build_stage eq "cnn_live_cropmatch"}]
set cnn_blackguard [expr {$build_stage eq "cnn_live_blackguard"}]
set cnn_live [expr {$build_stage eq "cnn_live" || $build_stage eq "cnn_live_bd" || $cnn_cropmatch || $cnn_blackguard || $cnn_image_process}]
set cnn_artifact_dir [file join $root_dir pl_cnn artifacts int8_20261001_all]
if {$cnn_live} {
    set project_dir [file join $root_dir vivado camera_hdmi_720p_cnn_live]
    set delivery_dir [file join $workspace camera_hdmi_720p_cnn_live_delivery]
}
if {$cnn_cropmatch} {
    set project_dir [file join $root_dir vivado camera_hdmi_720p_cnn_cropmatch]
    set delivery_dir [file join $workspace camera_hdmi_720p_cnn_cropmatch_delivery]
    set cnn_artifact_dir [file join $root_dir pl_cnn experiments pl_crop_shadow_norm_20261009 model_int8_trial2_final2]
}
if {$cnn_blackguard} {
    set project_dir [file join $root_dir vivado camera_hdmi_720p_cnn_blackguard]
    set delivery_dir [file join $workspace camera_hdmi_720p_cnn_blackguard_delivery]
    set cnn_artifact_dir [file join $root_dir pl_cnn experiments pl_crop_shadow_norm_20261009 model_int8_trial2_final2]
}
if {$cnn_image_process} {
    set project_dir [file join $root_dir vivado camera_hdmi_720p_cnn_image_process_newmodel]
    set delivery_dir [file join $workspace camera_hdmi_720p_newmodel_2026-10-16_delivery]
    set cnn_artifact_dir [file join $root_dir pl_cnn artifacts int8_newmodel_20261016]
}
if {$shadow_compare} {
    set project_dir [file join $root_dir vivado camera_hdmi_720p_shadow_compare]
    set delivery_dir [file join $workspace camera_hdmi_720p_shadow_compare_delivery]
}
if {$sixpanel_cnn} {
    set project_dir [file join $root_dir vivado camera_hdmi_720p_sixpanel_cnn]
    set delivery_dir [file join $workspace camera_hdmi_720p_sixpanel_cnn_delivery]
}
if {$python_sixpanel} {
    set project_dir [file join $root_dir vivado camera_hdmi_720p_python_sixpanel]
    set delivery_dir [file join $workspace camera_hdmi_720p_python_sixpanel_delivery]
}
if {$fpga_sixpanel} {
    set project_name fpga_sixpanel_project
    set build_tag [expr {[info exists ::env(STAR_ANISE_BUILD_TAG)] ? $::env(STAR_ANISE_BUILD_TAG) : "14"}]
    set project_dir [file join $workspace _vivado_fpga_sixpanel_build$build_tag]
    set delivery_dir [file join $workspace camera_hdmi_720p_fpga_sixpanel_delivery]
}
if {$fpga_mask_compare && !$python_sixpanel} {
    # Keep the Vivado hierarchy short enough for Windows' MAX_PATH limit.
    set project_name fpga_mask_project
    set project_dir [file join $workspace _vivado_fpga_mask]
    set delivery_dir [file join $workspace camera_hdmi_720p_fpga_mask_compare_delivery]
}
set delivery_dir $::env(STAR_ANISE_ISOLATED_DELIVERY)
set overlay_dir $::env(STAR_ANISE_ISOLATED_OVERLAY)
set vga_full_neg [expr {$build_stage eq "vga_full_neg" || $build_stage eq "vga_full_neg_bd"}]
set vga_full [expr {$build_stage eq "vga_full" || $build_stage eq "vga_full_bd" || $vga_full_neg}]
set hdmi_direct_raster [expr {$vga_full || $cnn_live || $image_processing || $fpga_mask_compare || $python_sixpanel || $fpga_sixpanel}]
set raster_mode [expr {$build_stage eq "raster_test" || $build_stage eq "raster_stream_test" || $build_stage eq "raster_stress_test" || $raster_mux_test}]
set tx_test_mode [expr {$build_stage eq "tx_test" || $build_stage eq "stream_data_test" || $build_stage eq "stream_sync_test" || $build_stage eq "stream_de_test" || $raster_mode || $bram_live || $vga_full}]
set stream_data_test [expr {$build_stage eq "stream_data_test"}]
set stream_sync_test [expr {$build_stage eq "stream_sync_test"}]
set stream_de_test [expr {$build_stage eq "stream_de_test"}]
file mkdir $project_dir; file mkdir $delivery_dir; file mkdir $overlay_dir
set_param board.repoPaths [list [file join $root_dir board_files]]
create_project $project_name $project_dir -part xc7z020clg400-1 -force
set_property board_part www.digilentinc.com:pynq-z1:part0:1.0 [current_project]
set_property target_language Verilog [current_project]
if {$fpga_sixpanel} {
    if {[info exists ::env(STAR_ANISE_HLS_IP_ROOT)] && [file exists [file join $::env(STAR_ANISE_HLS_IP_ROOT) component.xml]]} {
        set hls_ip_root $::env(STAR_ANISE_HLS_IP_ROOT)
    } else {
        set hls_ip_root [file join $workspace camera_hdmi_720p_fpga_sixpanel_delivery ip_repo sixpanel_accel]
    }
    if {![file exists [file join $hls_ip_root component.xml]]} { error "sixpanel_accel IP package not found. Set STAR_ANISE_HLS_IP_ROOT or build the HLS IP first." }
    set rgb_ip_root [file join $workspace camera_hdmi_720p_fpga_sixpanel ip_repo rgb2dvi_compat]
    set_property ip_repo_paths [list $hls_ip_root [file dirname $rgb_ip_root]] [current_project]
    update_ip_catalog -rebuild
}
set rtl_files [list \
 [file join $root_dir src camera_clock_buffer.v] \
 [file join $root_dir src dvp_rgb565_rx.v] \
 [file join $root_dir src camera_status_cdc.v] \
 [file join $root_dir src rgb565_to_rgb888_axis.v] \
 [file join $root_dir src axis_letterbox_720p.v] \
 [file join $root_dir src axis_rgb888_register_slice.v] \
 [file join $root_dir src axis_brightness_contrast_rgb565.v] \
 [file join $root_dir src axis_shadow_compare_rgb565.v] \
 [file join $root_dir src axis_fpga_mask_compare_rgb565.v] \
 [file join $root_dir src pl_shadow_boost_button.v] \
 [file join $root_dir src video_status_pack.v] \
 [file join $root_dir src hdmi_clocking_720p.v] \
 [file join $root_dir src hdmi_raster_test.v] \
 [file join $root_dir src hdmi_pixel_mux.v] \
 [file join $root_dir src hdmi_bram_raster.v] \
 [file join $root_dir src hdmi_vga_axis_raster.v] \
 [file join $root_dir src pl_cnn_result_box_cdc.v] \
 [file join $root_dir pl_cnn rtl pl_frame_vote.v] \
 [file join $root_dir pl_cnn rtl axis_box_overlay_720p.v] \
 [file join $root_dir pl_cnn rtl axis_object_locator_640x480.v] \
 [file join $root_dir pl_cnn rtl axis_roi_crop_640x480.v] \
 [file join $root_dir pl_cnn rtl axis_roi_frame_queue.v] \
 [file join $root_dir pl_cnn rtl pl_cnn_button_trigger.v] \
 [file join $root_dir pl_cnn rtl axis_frame_sof_marker.v] \
 [file join $root_dir pl_cnn rtl pl_cnn_control_unpack.v] \
 [file join $root_dir pl_cnn rtl pl_cnn_result_box_latch.v] \
 [file join $root_dir pl_cnn rtl pl_int8_mac_array.v] \
 [file join $root_dir pl_cnn rtl pl_int8_requant.v] \
 [file join $root_dir pl_cnn rtl pl_int8_dot_product.v] \
 [file join $root_dir pl_cnn rtl pl_int8_vector_conv.v] \
 [file join $root_dir pl_cnn rtl axis_int8_pointwise_layer.v] \
 [file join $root_dir pl_cnn rtl pl_int8_depthwise_conv.v] \
 [file join $root_dir pl_cnn rtl axis_int8_frame_pad.v] \
 [file join $root_dir pl_cnn rtl axis_int8_window3x3.v] \
 [file join $root_dir pl_cnn rtl axis_int8_depthwise_layer.v] \
 [file join $root_dir pl_cnn rtl axis_rgb3x3_window_s2.v] \
 [file join $root_dir pl_cnn rtl pl_stem_conv3x3_int8.v] \
 [file join $root_dir pl_cnn rtl axis_camera_stem_path.v] \
 [file join $root_dir pl_cnn rtl pl_int8_classifier.v] \
 [file join $root_dir pl_cnn rtl axis_shadow_chroma_norm.v] \
 [file join $root_dir pl_cnn rtl axis_pl_star_anise_cnn.v] \
 [file join $root_dir ip digilent_rgb2dvi src SyncAsync.vhd] \
 [file join $root_dir ip digilent_rgb2dvi src SyncAsyncReset.vhd] \
 [file join $root_dir ip digilent_rgb2dvi src ClockGen.vhd] \
 [file join $root_dir ip digilent_rgb2dvi src DVI_Constants.vhd] \
 [file join $root_dir ip digilent_rgb2dvi src OutputSERDES.vhd] \
 [file join $root_dir ip digilent_rgb2dvi src TMDS_Encoder.vhd] \
 [file join $root_dir ip digilent_rgb2dvi src rgb2dvi.vhd]]
if {$fpga_sixpanel} {
    set rtl_files [list \
        [file join $root_dir src camera_clock_buffer.v] \
        [file join $root_dir src dvp_rgb565_rx.v] \
        [file join $root_dir src camera_status_cdc.v] \
        [file join $root_dir src hdmi_clocking_720p.v] \
        [file join $workspace camera_hdmi_720p_fpga_sixpanel rtl vision_tip_count_classifier.v] \
        [file join $workspace camera_hdmi_720p_fpga_sixpanel rtl vision_result_button_latch.v] \
        [file join $root_dir src button_sync4.v] \
        [file join $workspace camera_hdmi_720p_python_sixpanel_delivery hdmi_vga_axis_raster.v]]
}
add_files -norecurse $rtl_files
set model_parameters [glob -nocomplain \
 [file join $cnn_artifact_dir *.mem]]
add_files -norecurse $model_parameters
update_compile_order -fileset sources_1
create_bd_design $design_name
if {$fpga_sixpanel} {
    set tx [create_bd_cell -type ip -vlnv star-anise.fpga:user:rgb2dvi_compat:1.0 rgb2dvi_0]
} else {
    set tx [create_bd_cell -type module -reference rgb2dvi_compat rgb2dvi_0]
}

# PS: GP0 configures AXI peripherals; HP0 carries both 64-bit VDMA masters.
set ps [create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:* processing_system7_0]
apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 -config {make_external "FIXED_IO, DDR" apply_board_preset "1" Master "Disable" Slave "Disable"} $ps
set_property -dict [list CONFIG.PCW_USE_M_AXI_GP0 {1} CONFIG.PCW_USE_S_AXI_HP0 {1} CONFIG.PCW_USE_FABRIC_INTERRUPT {1} CONFIG.PCW_IRQ_F2P_INTR {1} CONFIG.PCW_EN_CLK0_PORT {1} CONFIG.PCW_EN_RST0_PORT {1} CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100.000000}] $ps

set iic [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_iic:* axi_iic_0]
set_property -dict [list CONFIG.TEN_BIT_ADR {7_bit} CONFIG.IIC_FREQ_KHZ {100} CONFIG.USE_BOARD_FLOW {false} CONFIG.IIC_BOARD_INTERFACE {Custom}] $iic
set cam_rst_gpio [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:* axi_gpio_0]
set_property -dict [list CONFIG.C_GPIO_WIDTH {1} CONFIG.C_ALL_OUTPUTS {1} CONFIG.C_IS_DUAL {0} CONFIG.C_DOUT_DEFAULT {0x00000000}] $cam_rst_gpio
set cam_stat_gpio [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:* axi_gpio_status]
set_property -dict [list CONFIG.C_GPIO_WIDTH {32} CONFIG.C_ALL_INPUTS {1} CONFIG.C_IS_DUAL {1} CONFIG.C_GPIO2_WIDTH {32} CONFIG.C_ALL_INPUTS_2 {1}] $cam_stat_gpio
set cam_diag_gpio [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:* axi_gpio_camera_diag]
set_property -dict [list CONFIG.C_GPIO_WIDTH {32} CONFIG.C_ALL_INPUTS {1} CONFIG.C_IS_DUAL {1} CONFIG.C_GPIO2_WIDTH {32} CONFIG.C_ALL_INPUTS_2 {1}] $cam_diag_gpio
if {$fpga_sixpanel} {
    set menu_gpio [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:* axi_gpio_menu]
    set_property -dict [list CONFIG.C_GPIO_WIDTH {1} CONFIG.C_ALL_OUTPUTS {1} CONFIG.C_IS_DUAL {1} CONFIG.C_GPIO2_WIDTH {4} CONFIG.C_ALL_INPUTS_2 {1} CONFIG.C_DOUT_DEFAULT {0x00000000}] $menu_gpio
    set button_sync [create_bd_cell -type module -reference button_sync4 button_sync4_0]
    set button0_slice [create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice:* xlslice_btn0]
    set_property -dict [list CONFIG.DIN_WIDTH {4} CONFIG.DIN_FROM {0} CONFIG.DIN_TO {0} CONFIG.DOUT_WIDTH {1}] $button0_slice
}
if {$python_sixpanel} {
    set python_result_gpio [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:* axi_gpio_python_result]
    set_property -dict [list CONFIG.C_GPIO_WIDTH {2} CONFIG.C_ALL_OUTPUTS {1} CONFIG.C_IS_DUAL {1} CONFIG.C_GPIO2_WIDTH {1} CONFIG.C_ALL_INPUTS_2 {1} CONFIG.C_DOUT_DEFAULT {0x00000000}] $python_result_gpio
    set result_valid_slice [create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice:* xlslice_python_result_valid]
    set_property -dict [list CONFIG.DIN_WIDTH {2} CONFIG.DIN_FROM {0} CONFIG.DIN_TO {0} CONFIG.DOUT_WIDTH {1}] $result_valid_slice
    set result_class_slice [create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice:* xlslice_python_result_class]
    set_property -dict [list CONFIG.DIN_WIDTH {2} CONFIG.DIN_FROM {1} CONFIG.DIN_TO {1} CONFIG.DOUT_WIDTH {1}] $result_class_slice
}
set vid_stat_gpio [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:* axi_gpio_video_status]
set_property -dict [list CONFIG.C_GPIO_WIDTH {32} CONFIG.C_ALL_INPUTS {1} CONFIG.C_IS_DUAL {1} CONFIG.C_GPIO2_WIDTH {32} CONFIG.C_ALL_INPUTS_2 {1}] $vid_stat_gpio
if {$raster_mux_test} {
    set pixel_source_gpio [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:* axi_gpio_pixel_source]
    set_property -dict [list CONFIG.C_GPIO_WIDTH {1} CONFIG.C_ALL_OUTPUTS {1} CONFIG.C_IS_DUAL {0} CONFIG.C_DOUT_DEFAULT {0x00000000}] $pixel_source_gpio
}
if {$bram_live} {
    set frame_bram_ctrl [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_bram_ctrl:* axi_bram_frame_ctrl]
    set_property -dict [list CONFIG.SINGLE_PORT_BRAM {1} CONFIG.DATA_WIDTH {32}] $frame_bram_ctrl
    set frame_bram [create_bd_cell -type ip -vlnv xilinx.com:ip:blk_mem_gen:* frame_bram]
    set_property -dict [list CONFIG.Memory_Type {True_Dual_Port_RAM} CONFIG.Write_Width_A {32} CONFIG.Read_Width_A {32} CONFIG.Write_Depth_A {9600} CONFIG.Write_Width_B {32} CONFIG.Read_Width_B {32} CONFIG.Enable_B {Use_ENB_Pin} CONFIG.Use_Byte_Write_Enable {true} CONFIG.Byte_Size {8}] $frame_bram
    connect_bd_intf_net [get_bd_intf_pins axi_bram_frame_ctrl/BRAM_PORTA] [get_bd_intf_pins frame_bram/BRAM_PORTA]
}

set vdma [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_vdma:* axi_vdma_0]
set_property -dict [list CONFIG.c_include_sg {0} CONFIG.c_include_mm2s {1} CONFIG.c_include_s2mm {1} CONFIG.c_num_fstores {3} CONFIG.c_m_axi_mm2s_data_width {64} CONFIG.c_m_axi_s2mm_data_width {64} CONFIG.c_m_axis_mm2s_tdata_width {16} CONFIG.c_mm2s_linebuffer_depth {1024} CONFIG.c_s2mm_linebuffer_depth {1024} CONFIG.c_mm2s_max_burst_length {16} CONFIG.c_s2mm_max_burst_length {16} CONFIG.c_include_mm2s_sf {1} CONFIG.c_include_s2mm_sf {1}] $vdma
if {$fpga_sixpanel} {
    set sixpanel [create_bd_cell -type ip -vlnv xilinx.com:hls:sixpanel_accel:1.0 sixpanel_accel_0]
    set tip_classifier [create_bd_cell -type module -reference vision_tip_count_classifier vision_tip_count_classifier_0]
    set result_latch [create_bd_cell -type module -reference vision_result_button_latch vision_result_button_latch_0]
    set class_bit_slice [create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice:* xlslice_result_class_bit]
    set_property -dict [list CONFIG.DIN_WIDTH {2} CONFIG.DIN_FROM {0} CONFIG.DIN_TO {0} CONFIG.DOUT_WIDTH {1}] $class_bit_slice
    set invalid_bit_slice [create_bd_cell -type ip -vlnv xilinx.com:ip:xlslice:* xlslice_result_invalid_bit]
    set_property -dict [list CONFIG.DIN_WIDTH {2} CONFIG.DIN_FROM {1} CONFIG.DIN_TO {1} CONFIG.DOUT_WIDTH {1}] $invalid_bit_slice
}
if {$cnn_live} {
    set cnn_ctrl [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:* axi_gpio_cnn_control]
    set_property -dict [list CONFIG.C_GPIO_WIDTH {32} CONFIG.C_ALL_OUTPUTS {1} CONFIG.C_IS_DUAL {0} CONFIG.C_DOUT_DEFAULT {0x0003b18d}] $cnn_ctrl
    set cnn_result_gpio [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:* axi_gpio_cnn_result]
    set result_gpio2_width [expr {$cnn_image_process ? 13 : 2}]
    set_property -dict [list CONFIG.C_GPIO_WIDTH {32} CONFIG.C_ALL_INPUTS {1} CONFIG.C_IS_DUAL {1} CONFIG.C_GPIO2_WIDTH $result_gpio2_width CONFIG.C_ALL_INPUTS_2 {1}] $cnn_result_gpio
    set cnn_debug_gpio [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:* axi_gpio_cnn_debug]
    set_property -dict [list CONFIG.C_GPIO_WIDTH {32} CONFIG.C_ALL_INPUTS {1} CONFIG.C_IS_DUAL {1} CONFIG.C_GPIO2_WIDTH {32} CONFIG.C_ALL_INPUTS_2 {1}] $cnn_debug_gpio
    set cnn_queue_status [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:* xlconcat_cnn_queue_status]
    set_property -dict [list CONFIG.NUM_PORTS {2} CONFIG.IN0_WIDTH {16} CONFIG.IN1_WIDTH {16}] $cnn_queue_status
}
set intc [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_intc:* axi_intc_0]

set ctrl_ic [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:* axi_interconnect_ctrl]
set ctrl_mi_count [expr {$cnn_live ? 11 : ($fpga_sixpanel ? 10 : ($python_sixpanel ? 9 : (($raster_mux_test || $bram_live) ? 9 : 8)))}]
set_property -dict [list CONFIG.NUM_SI {1} CONFIG.NUM_MI $ctrl_mi_count] $ctrl_ic
set mem_ic [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:* axi_interconnect_mem]
set mem_si_count [expr {$fpga_sixpanel ? 6 : 2}]
set_property -dict [list CONFIG.NUM_SI $mem_si_count CONFIG.NUM_MI {1}] $mem_ic

# Deep async FIFO decouples camera PCLK from 100 MHz VDMA.  32768 entries
# absorb transient VDMA/DDR back-pressure; full is counted at the DVP source.
set fifo [create_bd_cell -type ip -vlnv xilinx.com:ip:axis_data_fifo:* axis_camera_fifo]
set_property -dict [list CONFIG.TDATA_NUM_BYTES {2} CONFIG.TUSER_WIDTH {1} CONFIG.HAS_TLAST {1} CONFIG.FIFO_DEPTH {32768} CONFIG.IS_ACLK_ASYNC {1}] $fifo
if {$cnn_live} {
    if {$shadow_compare} {
        set cnn_broadcaster [create_bd_cell -type ip -vlnv xilinx.com:ip:axis_broadcaster:* axis_camera_raw_splitter]
        set_property -dict [list CONFIG.NUM_MI {2} CONFIG.S_TDATA_NUM_BYTES {2} CONFIG.M_TDATA_NUM_BYTES {2} CONFIG.S_TUSER_WIDTH {1} CONFIG.M_TUSER_WIDTH {1} CONFIG.HAS_TLAST {1}] $cnn_broadcaster
    } else {
        set cnn_broadcaster [create_bd_cell -type ip -vlnv xilinx.com:ip:axis_broadcaster:* axis_cnn_broadcaster]
        set_property -dict [list CONFIG.NUM_MI {2} CONFIG.S_TDATA_NUM_BYTES {2} CONFIG.M_TDATA_NUM_BYTES {2} CONFIG.S_TUSER_WIDTH {1} CONFIG.M_TUSER_WIDTH {1} CONFIG.HAS_TLAST {1}] $cnn_broadcaster
    }
    set cnn_fifo [create_bd_cell -type ip -vlnv xilinx.com:ip:axis_data_fifo:* axis_cnn_camera_fifo]
    set_property -dict [list CONFIG.TDATA_NUM_BYTES {2} CONFIG.TUSER_WIDTH {1} CONFIG.HAS_TLAST {1} CONFIG.FIFO_DEPTH {4096} CONFIG.IS_ACLK_ASYNC {1}] $cnn_fifo
}
if {$hdmi_direct_raster} {
    set hdmi_fifo [create_bd_cell -type ip -vlnv xilinx.com:ip:axis_data_fifo:* axis_hdmi_fifo]
    set_property -dict [list CONFIG.TDATA_NUM_BYTES {2} CONFIG.TUSER_WIDTH {1} CONFIG.HAS_TLAST {1} CONFIG.FIFO_DEPTH {8192} CONFIG.IS_ACLK_ASYNC {1}] $hdmi_fifo
}

# Static 720p equivalent of Base Overlay axi_dynclk.  The MMCM emits one
# unbuffered 371.25 MHz clock; hdmi_clocking_720p uses BUFIO and BUFR /5 to
# create phase-aligned serial and 74.25 MHz pixel clocks.
set dynclk [create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wiz:* clk_wiz_720p]
set_property -dict [list CONFIG.PRIM_SOURCE {No_buffer} CONFIG.PRIM_IN_FREQ {100.000} CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {371.250} CONFIG.CLKOUT1_DRIVES {No_buffer} CONFIG.NUM_OUT_CLKS {1} CONFIG.USE_PHASE_ALIGNMENT {false} CONFIG.MMCM_COMPENSATION {INTERNAL} CONFIG.FEEDBACK_SOURCE {FDBK_AUTO} CONFIG.RESET_TYPE {ACTIVE_HIGH} CONFIG.USE_LOCKED {true}] $dynclk

set vtc [create_bd_cell -type ip -vlnv xilinx.com:ip:v_tc:* v_tc_0]
set_property -dict [list CONFIG.VIDEO_MODE {Custom} CONFIG.HAS_AXI4_LITE {true} CONFIG.enable_detection {false} CONFIG.enable_generation {true} CONFIG.GEN_HACTIVE_SIZE {1280} CONFIG.GEN_HFRAME_SIZE {1650} CONFIG.GEN_HSYNC_START {1390} CONFIG.GEN_HSYNC_END {1430} CONFIG.GEN_VACTIVE_SIZE {720} CONFIG.GEN_F0_VFRAME_SIZE {750} CONFIG.GEN_F0_VSYNC_VSTART {725} CONFIG.GEN_F0_VSYNC_VEND {730} CONFIG.GEN_F0_VBLANK_HSTART {1280} CONFIG.GEN_F0_VBLANK_HEND {1650} CONFIG.GEN_F0_VSYNC_HSTART {1390} CONFIG.GEN_F0_VSYNC_HEND {1430} CONFIG.GEN_HSYNC_POLARITY {High} CONFIG.GEN_VSYNC_POLARITY {High} CONFIG.GEN_VIDEO_FORMAT {RGB}] $vtc
if {!$hdmi_direct_raster} {
    set vidout [create_bd_cell -type ip -vlnv xilinx.com:ip:v_axi4s_vid_out:* v_axi4s_vid_out_0]
    set_property -dict [list CONFIG.C_HAS_ASYNC_CLK {1} CONFIG.C_ADDR_WIDTH {12} CONFIG.C_HYSTERESIS_LEVEL {1024} CONFIG.C_NATIVE_COMPONENT_WIDTH {8} CONFIG.C_PIXELS_PER_CLOCK {1} CONFIG.C_S_AXIS_VIDEO_DATA_WIDTH {8} CONFIG.C_S_AXIS_VIDEO_FORMAT {2} CONFIG.C_VTG_MASTER_SLAVE {1}] $vidout
}

set rst_sys [create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:* rst_sys_100m]
set rst_cam [create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:* rst_cam_pclk]
set rst_pix [create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:* rst_video_720p]
set irqcat [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:* xlconcat_irq]
set_property CONFIG.NUM_PORTS {2} $irqcat
set one [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:* xlconstant_one]
set_property -dict [list CONFIG.CONST_WIDTH {1} CONFIG.CONST_VAL {1}] $one

set cbuf [create_bd_cell -type module -reference camera_clock_buffer camera_clock_buffer_0]
set rx [create_bd_cell -type module -reference dvp_rgb565_rx dvp_rgb565_rx_0]
set_property -dict [list CONFIG.FRAME_WIDTH {640} CONFIG.FRAME_HEIGHT {480} CONFIG.BYTE_SWAP {0}] $rx
if {$image_processing} {
    set image_filter [create_bd_cell -type module -reference axis_brightness_contrast_rgb565 axis_brightness_contrast_rgb565_0]
    set brightness_value [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:* xlconstant_brightness_value]
    set_property -dict [list CONFIG.CONST_WIDTH {8} CONFIG.CONST_VAL {32}] $brightness_value
    set contrast_value [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:* xlconstant_contrast_value]
    set_property -dict [list CONFIG.CONST_WIDTH {16} CONFIG.CONST_VAL {0x0180}] $contrast_value
}
if {$cnn_live} {
    set cnn_crop [create_bd_cell -type module -reference axis_roi_crop_640x480 axis_roi_crop_640x480_0]
    set cnn_locator [create_bd_cell -type module -reference axis_object_locator_640x480 axis_object_locator_640x480_0]
    set cnn_frame_queue [create_bd_cell -type module -reference axis_roi_frame_queue axis_roi_frame_queue_0]
    set cnn_stream_slice [create_bd_cell -type module -reference axis_rgb888_register_slice axis_rgb888_register_slice_0]
    set cnn_control_unpack [create_bd_cell -type module -reference pl_cnn_control_unpack pl_cnn_control_unpack_0]
    set cnn_core [create_bd_cell -type module -reference axis_pl_star_anise_cnn axis_pl_star_anise_cnn_0]
    set_property CONFIG.ARTIFACT_DIR $cnn_artifact_dir $cnn_core
    # Synthesize the optional low-cost shadow normalization stage. The model
    # must be retrained with matching preprocessing before any board demo.
    set_property CONFIG.SHADOW_NORM_ENABLE {1} $cnn_core
    set cnn_result [create_bd_cell -type module -reference pl_cnn_result_box_latch pl_cnn_result_box_latch_0]
    set cnn_result_cdc [create_bd_cell -type module -reference pl_cnn_result_box_cdc pl_cnn_result_box_cdc_0]
    set cnn_result_concat [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:* xlconcat_cnn_result]
    if {$cnn_image_process} {
        set_property -dict [list CONFIG.NUM_PORTS {6} CONFIG.IN5_WIDTH {8}] $cnn_result_concat
    } else {
        set_property CONFIG.NUM_PORTS {2} $cnn_result_concat
    }
    set cnn_gate_one [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:* xlconstant_cnn_gate_one]
    set_property -dict [list CONFIG.CONST_WIDTH {1} CONFIG.CONST_VAL {1}] $cnn_gate_one
    set cnn_gate_zero [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:* xlconstant_cnn_gate_zero]
    set_property -dict [list CONFIG.CONST_WIDTH {1} CONFIG.CONST_VAL {0}] $cnn_gate_zero
    if {$cnn_image_process} {
        set cnn_button [create_bd_cell -type module -reference pl_cnn_button_trigger pl_cnn_button_trigger_0]
        set result_clear_or [create_bd_cell -type ip -vlnv xilinx.com:ip:util_vector_logic:* util_vector_logic_result_clear]
        set_property -dict [list CONFIG.C_OPERATION {or} CONFIG.C_SIZE {1}] $result_clear_or
    }
}
if {$vga_full_neg} { set_property CONFIG.SAMPLE_NEGEDGE {1} $rx }
set cdc [create_bd_cell -type module -reference camera_status_cdc camera_status_cdc_0]
if {$shadow_compare} {
    set shadow_pair [create_bd_cell -type module -reference axis_shadow_compare_rgb565 axis_shadow_compare_rgb565_0]
    set shadow_boost_button [create_bd_cell -type module -reference pl_shadow_boost_button pl_shadow_boost_button_0]
} elseif {$fpga_mask_compare} {
    set shadow_pair [create_bd_cell -type module -reference axis_fpga_mask_compare_rgb565 axis_shadow_compare_rgb565_0]
}
if {!$hdmi_direct_raster} {
    set expand [create_bd_cell -type module -reference rgb565_to_rgb888_axis rgb565_to_rgb888_axis_0]
    set letterbox [create_bd_cell -type module -reference axis_letterbox_720p axis_letterbox_720p_0]
}
set hdmi_clocks [create_bd_cell -type module -reference hdmi_clocking_720p hdmi_clocking_720p_0]
if {$bram_live} {
    set frame_raster [create_bd_cell -type module -reference hdmi_bram_raster hdmi_bram_raster_0]
    connect_bd_net [get_bd_pins hdmi_bram_raster_0/bram_addr] [get_bd_pins frame_bram/addrb]
    connect_bd_net [get_bd_pins frame_bram/doutb] [get_bd_pins hdmi_bram_raster_0/bram_dout]
    connect_bd_net [get_bd_pins xlconstant_one/dout] [get_bd_pins frame_bram/enb]
    set bram_zero [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:* xlconstant_bram_zero]
    set_property -dict [list CONFIG.CONST_WIDTH {32} CONFIG.CONST_VAL {0}] $bram_zero
    connect_bd_net [get_bd_pins xlconstant_bram_zero/dout] [get_bd_pins frame_bram/dinb]
    set bram_no_write [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:* xlconstant_bram_no_write]
    set_property -dict [list CONFIG.CONST_WIDTH {4} CONFIG.CONST_VAL {0}] $bram_no_write
    connect_bd_net [get_bd_pins xlconstant_bram_no_write/dout] [get_bd_pins frame_bram/web]
} elseif {$hdmi_direct_raster} {
    set full_raster [create_bd_cell -type module -reference hdmi_vga_axis_raster hdmi_vga_axis_raster_0]
    if {$shadow_compare || $fpga_mask_compare} { set_property CONFIG.COMPARE_MODE {1} $full_raster }
    if {$sixpanel_cnn || $python_sixpanel || $fpga_sixpanel} { set_property CONFIG.SIX_PANEL_MODE {1} $full_raster }
    if {$cnn_live} {
        foreach {signal source} {
            box_enable pl_cnn_result_box_cdc_0/dst_box_enable
            box_x0 pl_cnn_result_box_cdc_0/dst_box_x0
            box_x1 pl_cnn_result_box_cdc_0/dst_box_x1
            box_y0 pl_cnn_result_box_cdc_0/dst_box_y0
            box_y1 pl_cnn_result_box_cdc_0/dst_box_y1
            result_valid pl_cnn_result_box_cdc_0/dst_result_valid
            result_class pl_cnn_result_box_cdc_0/dst_result_class
        } {
            connect_bd_net [get_bd_pins $source] [get_bd_pins hdmi_vga_axis_raster_0/$signal]
        }
    } else {
        foreach {signal width} {box_enable 1 box_x0 10 box_x1 10 box_y0 9 box_y1 9} {
            set box_zero [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:* xlconstant_$signal]
            set_property -dict [list CONFIG.CONST_WIDTH $width CONFIG.CONST_VAL {0}] $box_zero
            connect_bd_net [get_bd_pins xlconstant_$signal/dout] [get_bd_pins hdmi_vga_axis_raster_0/$signal]
        }
        if {$python_sixpanel} {
            connect_bd_net [get_bd_pins axi_gpio_python_result/gpio_io_o] [get_bd_pins xlslice_python_result_valid/Din] [get_bd_pins xlslice_python_result_class/Din]
            connect_bd_net [get_bd_pins xlslice_python_result_valid/Dout] [get_bd_pins hdmi_vga_axis_raster_0/result_valid]
            connect_bd_net [get_bd_pins xlslice_python_result_class/Dout] [get_bd_pins hdmi_vga_axis_raster_0/result_class]
            set invalid_zero [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:* xlconstant_result_invalid]
            set_property -dict [list CONFIG.CONST_WIDTH {1} CONFIG.CONST_VAL {0}] $invalid_zero
            connect_bd_net [get_bd_pins xlconstant_result_invalid/dout] [get_bd_pins hdmi_vga_axis_raster_0/result_invalid]
        } elseif {$fpga_sixpanel} {
            connect_bd_net [get_bd_pins vision_result_button_latch_0/latched_valid] [get_bd_pins hdmi_vga_axis_raster_0/result_valid]
            connect_bd_net [get_bd_pins vision_result_button_latch_0/latched_class] [get_bd_pins xlslice_result_class_bit/Din]
            connect_bd_net [get_bd_pins xlslice_result_class_bit/Dout] [get_bd_pins hdmi_vga_axis_raster_0/result_class]
            connect_bd_net [get_bd_pins vision_result_button_latch_0/latched_class] [get_bd_pins xlslice_result_invalid_bit/Din]
            connect_bd_net [get_bd_pins xlslice_result_invalid_bit/Dout] [get_bd_pins hdmi_vga_axis_raster_0/result_invalid]
        } else {
            foreach {signal width} {result_valid 1 result_class 1 result_invalid 1} {
                set result_zero [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:* xlconstant_$signal]
                set_property -dict [list CONFIG.CONST_WIDTH $width CONFIG.CONST_VAL {0}] $result_zero
                connect_bd_net [get_bd_pins xlconstant_$signal/dout] [get_bd_pins hdmi_vga_axis_raster_0/$signal]
            }
        }
    }
} elseif {$raster_mode} {
        set raster [create_bd_cell -type module -reference hdmi_raster_test hdmi_raster_test_0]
        if {$build_stage eq "raster_stress_test"} {
            connect_bd_net [get_bd_pins xlconstant_one/dout] [get_bd_pins hdmi_raster_test_0/stress_mode]
        } else {
            set zero [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:* xlconstant_raster_pattern]
            set_property -dict [list CONFIG.CONST_WIDTH {1} CONFIG.CONST_VAL {0}] $zero
            connect_bd_net [get_bd_pins xlconstant_raster_pattern/dout] [get_bd_pins hdmi_raster_test_0/stress_mode]
        }
}
if {$raster_mux_test} {
    set pixel_mux [create_bd_cell -type module -reference hdmi_pixel_mux hdmi_pixel_mux_0]
    connect_bd_net [get_bd_pins axi_gpio_pixel_source/gpio_io_o] [get_bd_pins hdmi_pixel_mux_0/select_live]
    connect_bd_net [get_bd_pins hdmi_raster_test_0/pixel_data] [get_bd_pins hdmi_pixel_mux_0/test_pixel]
    connect_bd_net [get_bd_pins v_axi4s_vid_out_0/vid_data] [get_bd_pins hdmi_pixel_mux_0/live_pixel]
    connect_bd_net [get_bd_pins hdmi_pixel_mux_0/pixel_data] [get_bd_pins rgb2dvi_0/vid_pData]
}
if {!$bram_live && !$hdmi_direct_raster} {
    set vpack [create_bd_cell -type module -reference video_status_pack video_status_pack_0]
}
if {$tx_test_mode} {
    set tx_test_rgb [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:* xlconstant_tx_test_rgb]
    set_property -dict [list CONFIG.CONST_WIDTH {24} CONFIG.CONST_VAL {0x808080}] $tx_test_rgb
}

# External ports: exactly the existing camera wiring, IIC, reset and HDMI OUT.
set cam_d [create_bd_port -dir I -from 7 -to 0 cam_d]
set cam_pclk [create_bd_port -dir I -type clk cam_pclk]; set_property CONFIG.FREQ_HZ {48000000} $cam_pclk
set cam_vsync [create_bd_port -dir I cam_vsync]; set cam_href [create_bd_port -dir I cam_href]
set cam_rst [create_bd_port -dir O cam_rst_n]
if {$python_sixpanel} { set btn0 [create_bd_port -dir I btn0] }
if {$fpga_sixpanel} { set buttons [create_bd_port -dir I -from 3 -to 0 buttons] }
if {$image_processing} { set sw_mode [create_bd_port -dir I -from 1 -to 0 sw_mode] }
if {$cnn_image_process} { set btn0 [create_bd_port -dir I btn0] }
if {$shadow_compare} { set btn1 [create_bd_port -dir I btn1] }
set hcp [create_bd_port -dir O hdmi_out_clk_p]; set hcn [create_bd_port -dir O hdmi_out_clk_n]
set hdp [create_bd_port -dir O -from 2 -to 0 hdmi_out_data_p]; set hdn [create_bd_port -dir O -from 2 -to 0 hdmi_out_data_n]
set iic_ext [create_bd_intf_port -mode Master -vlnv xilinx.com:interface:iic_rtl:1.0 cam_iic]

connect_bd_net $cam_pclk [get_bd_pins camera_clock_buffer_0/cam_pclk]
connect_bd_net [get_bd_pins camera_clock_buffer_0/cam_pclk_buf] [get_bd_pins dvp_rgb565_rx_0/cam_pclk]
connect_bd_net $cam_d [get_bd_pins dvp_rgb565_rx_0/cam_d]; connect_bd_net $cam_vsync [get_bd_pins dvp_rgb565_rx_0/cam_vsync]; connect_bd_net $cam_href [get_bd_pins dvp_rgb565_rx_0/cam_href]
connect_bd_intf_net $iic_ext [get_bd_intf_pins axi_iic_0/IIC]
connect_bd_net $cam_rst [get_bd_pins axi_gpio_0/gpio_io_o]
if {$python_sixpanel} { connect_bd_net $btn0 [get_bd_pins axi_gpio_python_result/gpio2_io_i] }
if {$fpga_sixpanel} {
    connect_bd_net $buttons [get_bd_pins button_sync4_0/buttons_async]
    connect_bd_net [get_bd_pins button_sync4_0/buttons_sync] [get_bd_pins axi_gpio_menu/gpio2_io_i]
    connect_bd_net [get_bd_pins button_sync4_0/buttons_sync] [get_bd_pins xlslice_btn0/Din]
    connect_bd_net [get_bd_pins xlslice_btn0/Dout] [get_bd_pins vision_result_button_latch_0/button]
}

if {$cnn_live} {
    if {$shadow_compare} {
        connect_bd_intf_net [get_bd_intf_pins dvp_rgb565_rx_0/M_AXIS] [get_bd_intf_pins axis_camera_raw_splitter/S_AXIS]
        connect_bd_intf_net [get_bd_intf_pins axis_camera_raw_splitter/M00_AXIS] [get_bd_intf_pins axis_camera_fifo/S_AXIS]
        connect_bd_intf_net [get_bd_intf_pins axis_camera_raw_splitter/M01_AXIS] [get_bd_intf_pins axis_brightness_contrast_rgb565_0/S_AXIS]
        connect_bd_intf_net [get_bd_intf_pins axis_brightness_contrast_rgb565_0/M_AXIS] [get_bd_intf_pins axis_cnn_camera_fifo/S_AXIS]
        connect_bd_net $sw_mode [get_bd_pins axis_brightness_contrast_rgb565_0/mode_sel]
        connect_bd_net [get_bd_pins xlconstant_brightness_value/dout] [get_bd_pins axis_brightness_contrast_rgb565_0/B_val]
        connect_bd_net [get_bd_pins xlconstant_contrast_value/dout] [get_bd_pins axis_brightness_contrast_rgb565_0/K_q8_8]
    } elseif {$cnn_image_process} {
        connect_bd_intf_net [get_bd_intf_pins dvp_rgb565_rx_0/M_AXIS] [get_bd_intf_pins axis_brightness_contrast_rgb565_0/S_AXIS]
        connect_bd_intf_net [get_bd_intf_pins axis_brightness_contrast_rgb565_0/M_AXIS] [get_bd_intf_pins axis_cnn_broadcaster/S_AXIS]
        connect_bd_net $sw_mode [get_bd_pins axis_brightness_contrast_rgb565_0/mode_sel]
        connect_bd_net [get_bd_pins xlconstant_brightness_value/dout] [get_bd_pins axis_brightness_contrast_rgb565_0/B_val]
        connect_bd_net [get_bd_pins xlconstant_contrast_value/dout] [get_bd_pins axis_brightness_contrast_rgb565_0/K_q8_8]
    } else {
        connect_bd_intf_net [get_bd_intf_pins dvp_rgb565_rx_0/M_AXIS] [get_bd_intf_pins axis_cnn_broadcaster/S_AXIS]
    }
    if {!$shadow_compare} {
        connect_bd_intf_net [get_bd_intf_pins axis_cnn_broadcaster/M00_AXIS] [get_bd_intf_pins axis_camera_fifo/S_AXIS]
        connect_bd_intf_net [get_bd_intf_pins axis_cnn_broadcaster/M01_AXIS] [get_bd_intf_pins axis_cnn_camera_fifo/S_AXIS]
    }
} else {
    if {$image_processing} {
        connect_bd_intf_net [get_bd_intf_pins dvp_rgb565_rx_0/M_AXIS] [get_bd_intf_pins axis_brightness_contrast_rgb565_0/S_AXIS]
        connect_bd_intf_net [get_bd_intf_pins axis_brightness_contrast_rgb565_0/M_AXIS] [get_bd_intf_pins axis_camera_fifo/S_AXIS]
        connect_bd_net $sw_mode [get_bd_pins axis_brightness_contrast_rgb565_0/mode_sel]
        connect_bd_net [get_bd_pins xlconstant_brightness_value/dout] [get_bd_pins axis_brightness_contrast_rgb565_0/B_val]
        connect_bd_net [get_bd_pins xlconstant_contrast_value/dout] [get_bd_pins axis_brightness_contrast_rgb565_0/K_q8_8]
    } else {
        connect_bd_intf_net [get_bd_intf_pins dvp_rgb565_rx_0/M_AXIS] [get_bd_intf_pins axis_camera_fifo/S_AXIS]
    }
}
if {$shadow_compare || $fpga_mask_compare} {
    connect_bd_intf_net [get_bd_intf_pins axis_camera_fifo/M_AXIS] [get_bd_intf_pins axis_shadow_compare_rgb565_0/S_AXIS]
    connect_bd_intf_net [get_bd_intf_pins axis_shadow_compare_rgb565_0/M_AXIS] [get_bd_intf_pins axi_vdma_0/S_AXIS_S2MM]
    if {$shadow_compare} {
        connect_bd_net $sw_mode [get_bd_pins axis_shadow_compare_rgb565_0/mode_sel]
        connect_bd_net $btn1 [get_bd_pins pl_shadow_boost_button_0/button_async]
        connect_bd_net [get_bd_pins pl_shadow_boost_button_0/boost_enable] [get_bd_pins axis_shadow_compare_rgb565_0/local_boost_enable]
    }
} else {
    connect_bd_intf_net [get_bd_intf_pins axis_camera_fifo/M_AXIS] [get_bd_intf_pins axi_vdma_0/S_AXIS_S2MM]
}
if {$hdmi_direct_raster} {
    connect_bd_intf_net [get_bd_intf_pins axi_vdma_0/M_AXIS_MM2S] [get_bd_intf_pins axis_hdmi_fifo/S_AXIS]
    connect_bd_intf_net [get_bd_intf_pins axis_hdmi_fifo/M_AXIS] [get_bd_intf_pins hdmi_vga_axis_raster_0/S_AXIS]
} else {
    connect_bd_intf_net [get_bd_intf_pins axi_vdma_0/M_AXIS_MM2S] [get_bd_intf_pins rgb565_to_rgb888_axis_0/S_AXIS]
    connect_bd_intf_net [get_bd_intf_pins rgb565_to_rgb888_axis_0/M_AXIS] [get_bd_intf_pins axis_letterbox_720p_0/S_AXIS]
    connect_bd_intf_net [get_bd_intf_pins axis_letterbox_720p_0/M_AXIS] [get_bd_intf_pins v_axi4s_vid_out_0/video_in]
    connect_bd_intf_net [get_bd_intf_pins v_tc_0/vtiming_out] [get_bd_intf_pins v_axi4s_vid_out_0/vtiming_in]
}
if {$cnn_live} {
    connect_bd_intf_net [get_bd_intf_pins axis_cnn_camera_fifo/M_AXIS] [get_bd_intf_pins axis_object_locator_640x480_0/S_AXIS]
    connect_bd_intf_net [get_bd_intf_pins axis_object_locator_640x480_0/M_AXIS] [get_bd_intf_pins axis_roi_crop_640x480_0/S_AXIS]
    connect_bd_intf_net [get_bd_intf_pins axis_roi_crop_640x480_0/M_AXIS] [get_bd_intf_pins axis_roi_frame_queue_0/S_AXIS]
    connect_bd_intf_net [get_bd_intf_pins axis_roi_frame_queue_0/M_AXIS] [get_bd_intf_pins axis_rgb888_register_slice_0/S_AXIS]
    connect_bd_intf_net [get_bd_intf_pins axis_rgb888_register_slice_0/M_AXIS] [get_bd_intf_pins axis_pl_star_anise_cnn_0/S_AXIS]
    connect_bd_net [get_bd_pins axis_object_locator_640x480_0/box_valid] [get_bd_pins axis_pl_star_anise_cnn_0/object_valid]
    if {$cnn_image_process} {
        connect_bd_net $btn0 [get_bd_pins pl_cnn_button_trigger_0/button_in]
        connect_bd_net [get_bd_pins axis_pl_star_anise_cnn_0/result_valid] [get_bd_pins pl_cnn_button_trigger_0/result_valid]
        connect_bd_net [get_bd_pins pl_cnn_button_trigger_0/run_active] [get_bd_pins axis_roi_frame_queue_0/capture_enable] [get_bd_pins axis_roi_frame_queue_0/output_enable]
        connect_bd_net [get_bd_pins pl_cnn_button_trigger_0/clear_pulse] [get_bd_pins axis_roi_frame_queue_0/flush]
        connect_bd_net [get_bd_pins pl_cnn_button_trigger_0/clear_pulse] [get_bd_pins util_vector_logic_result_clear/Op1]
        connect_bd_net [get_bd_pins pl_cnn_button_trigger_0/clear_pulse] [get_bd_pins axis_pl_star_anise_cnn_0/clear_vote]
        connect_bd_net [get_bd_pins pl_cnn_control_unpack_0/clear_result] [get_bd_pins util_vector_logic_result_clear/Op2]
        connect_bd_net [get_bd_pins util_vector_logic_result_clear/Res] [get_bd_pins pl_cnn_result_box_latch_0/clear]
    } else {
        connect_bd_net [get_bd_pins xlconstant_cnn_gate_one/dout] [get_bd_pins axis_roi_frame_queue_0/capture_enable] [get_bd_pins axis_roi_frame_queue_0/output_enable]
        connect_bd_net [get_bd_pins xlconstant_cnn_gate_zero/dout] [get_bd_pins axis_roi_frame_queue_0/flush] [get_bd_pins axis_pl_star_anise_cnn_0/clear_vote]
        connect_bd_net [get_bd_pins pl_cnn_control_unpack_0/clear_result] [get_bd_pins pl_cnn_result_box_latch_0/clear]
    }
    connect_bd_net [get_bd_pins axi_gpio_cnn_control/gpio_io_o] [get_bd_pins pl_cnn_control_unpack_0/control_word]
    connect_bd_net [get_bd_pins pl_cnn_control_unpack_0/crop_enable] [get_bd_pins axis_roi_crop_640x480_0/crop_enable]
    connect_bd_net [get_bd_pins axis_object_locator_640x480_0/box_valid] [get_bd_pins axis_roi_crop_640x480_0/object_valid]
    connect_bd_net [get_bd_pins axis_object_locator_640x480_0/crop_x0] [get_bd_pins axis_roi_crop_640x480_0/roi_x0]
    connect_bd_net [get_bd_pins axis_object_locator_640x480_0/crop_y0] [get_bd_pins axis_roi_crop_640x480_0/roi_y0]
    connect_bd_net [get_bd_pins axis_object_locator_640x480_0/box_valid] [get_bd_pins pl_cnn_result_box_latch_0/detected_box_valid]
    connect_bd_net [get_bd_pins axis_object_locator_640x480_0/box_x0] [get_bd_pins pl_cnn_result_box_latch_0/detected_box_x0]
    connect_bd_net [get_bd_pins axis_object_locator_640x480_0/box_x1] [get_bd_pins pl_cnn_result_box_latch_0/detected_box_x1]
    connect_bd_net [get_bd_pins axis_object_locator_640x480_0/box_y0] [get_bd_pins pl_cnn_result_box_latch_0/detected_box_y0]
    connect_bd_net [get_bd_pins axis_object_locator_640x480_0/box_y1] [get_bd_pins pl_cnn_result_box_latch_0/detected_box_y1]
    connect_bd_net [get_bd_pins pl_cnn_control_unpack_0/crop_enable] [get_bd_pins pl_cnn_result_box_latch_0/roi_enable]
    connect_bd_net [get_bd_pins axis_pl_star_anise_cnn_0/result_valid] [get_bd_pins pl_cnn_result_box_latch_0/result_valid]
    connect_bd_net [get_bd_pins axis_pl_star_anise_cnn_0/result_class] [get_bd_pins pl_cnn_result_box_latch_0/result_class]
    connect_bd_net [get_bd_pins pl_cnn_result_box_latch_0/box_enable] [get_bd_pins pl_cnn_result_box_cdc_0/src_box_enable]
    connect_bd_net [get_bd_pins pl_cnn_result_box_latch_0/box_x0] [get_bd_pins pl_cnn_result_box_cdc_0/src_box_x0]
    connect_bd_net [get_bd_pins pl_cnn_result_box_latch_0/box_x1] [get_bd_pins pl_cnn_result_box_cdc_0/src_box_x1]
    connect_bd_net [get_bd_pins pl_cnn_result_box_latch_0/box_y0] [get_bd_pins pl_cnn_result_box_cdc_0/src_box_y0]
    connect_bd_net [get_bd_pins pl_cnn_result_box_latch_0/box_y1] [get_bd_pins pl_cnn_result_box_cdc_0/src_box_y1]
    connect_bd_net [get_bd_pins pl_cnn_result_box_latch_0/recognized] [get_bd_pins xlconcat_cnn_result/In0]
    connect_bd_net [get_bd_pins pl_cnn_result_box_latch_0/recognized_class] [get_bd_pins xlconcat_cnn_result/In1]
    if {$cnn_image_process} {
        connect_bd_net [get_bd_pins pl_cnn_button_trigger_0/button_raw] [get_bd_pins xlconcat_cnn_result/In2]
        connect_bd_net [get_bd_pins pl_cnn_button_trigger_0/button_debounced] [get_bd_pins xlconcat_cnn_result/In3]
        connect_bd_net [get_bd_pins pl_cnn_button_trigger_0/run_active] [get_bd_pins xlconcat_cnn_result/In4]
        connect_bd_net [get_bd_pins pl_cnn_button_trigger_0/trigger_count] [get_bd_pins xlconcat_cnn_result/In5]
    }
    connect_bd_net [get_bd_pins axis_pl_star_anise_cnn_0/debug_status] [get_bd_pins axi_gpio_cnn_result/gpio_io_i]
    connect_bd_net [get_bd_pins pl_cnn_result_box_latch_0/recognized] [get_bd_pins pl_cnn_result_box_cdc_0/src_result_valid]
    connect_bd_net [get_bd_pins pl_cnn_result_box_latch_0/recognized_class] [get_bd_pins pl_cnn_result_box_cdc_0/src_result_class]
    connect_bd_net [get_bd_pins xlconcat_cnn_result/dout] [get_bd_pins axi_gpio_cnn_result/gpio2_io_i]
    connect_bd_net [get_bd_pins axis_roi_crop_640x480_0/debug_status] [get_bd_pins axi_gpio_cnn_debug/gpio_io_i]
    connect_bd_net [get_bd_pins axis_roi_frame_queue_0/dropped_frames] [get_bd_pins xlconcat_cnn_queue_status/In0]
    connect_bd_net [get_bd_pins axis_roi_frame_queue_0/completed_frames] [get_bd_pins xlconcat_cnn_queue_status/In1]
    connect_bd_net [get_bd_pins xlconcat_cnn_queue_status/dout] [get_bd_pins axi_gpio_cnn_debug/gpio2_io_i]
}
if {$hdmi_direct_raster} {
    connect_bd_net [get_bd_pins hdmi_vga_axis_raster_0/pixel_data] [get_bd_pins rgb2dvi_0/vid_pData]
    connect_bd_net [get_bd_pins hdmi_vga_axis_raster_0/data_enable] [get_bd_pins rgb2dvi_0/vid_pVDE]
    connect_bd_net [get_bd_pins hdmi_vga_axis_raster_0/hsync_n] [get_bd_pins rgb2dvi_0/vid_pHSync]
    connect_bd_net [get_bd_pins hdmi_vga_axis_raster_0/vsync_n] [get_bd_pins rgb2dvi_0/vid_pVSync]
} elseif {$tx_test_mode} {
    if {$bram_live} {
        connect_bd_net [get_bd_pins hdmi_bram_raster_0/pixel_data] [get_bd_pins rgb2dvi_0/vid_pData]
        connect_bd_net [get_bd_pins hdmi_bram_raster_0/data_enable] [get_bd_pins rgb2dvi_0/vid_pVDE]
        connect_bd_net [get_bd_pins hdmi_bram_raster_0/hsync_n] [get_bd_pins rgb2dvi_0/vid_pHSync]
        connect_bd_net [get_bd_pins hdmi_bram_raster_0/vsync_n] [get_bd_pins rgb2dvi_0/vid_pVSync]
    } elseif {$raster_mode} {
        if {$raster_mux_test} {
            # Pixel source is selected by the PS-controlled mux above.
        } elseif {$build_stage eq "raster_test" || $build_stage eq "raster_stress_test"} {
            connect_bd_net [get_bd_pins hdmi_raster_test_0/pixel_data] [get_bd_pins rgb2dvi_0/vid_pData]
        } else {
            connect_bd_net [get_bd_pins v_axi4s_vid_out_0/vid_data] [get_bd_pins rgb2dvi_0/vid_pData]
        }
        connect_bd_net [get_bd_pins hdmi_raster_test_0/data_enable] [get_bd_pins rgb2dvi_0/vid_pVDE]
        connect_bd_net [get_bd_pins hdmi_raster_test_0/hsync_n] [get_bd_pins rgb2dvi_0/vid_pHSync]
        connect_bd_net [get_bd_pins hdmi_raster_test_0/vsync_n] [get_bd_pins rgb2dvi_0/vid_pVSync]
    } elseif {$stream_data_test} {
        connect_bd_net [get_bd_pins v_axi4s_vid_out_0/vid_data] [get_bd_pins rgb2dvi_0/vid_pData]
    } else {
        connect_bd_net [get_bd_pins xlconstant_tx_test_rgb/dout] [get_bd_pins rgb2dvi_0/vid_pData]
    }
    if {!$raster_mode && !$bram_live} {
        if {$stream_sync_test} {
            connect_bd_net [get_bd_pins v_axi4s_vid_out_0/vid_active_video] [get_bd_pins rgb2dvi_0/vid_pVDE]
            connect_bd_net [get_bd_pins v_axi4s_vid_out_0/vid_hsync] [get_bd_pins rgb2dvi_0/vid_pHSync]
            connect_bd_net [get_bd_pins v_axi4s_vid_out_0/vid_vsync] [get_bd_pins rgb2dvi_0/vid_pVSync]
        } elseif {$stream_de_test} {
            connect_bd_net [get_bd_pins v_axi4s_vid_out_0/vid_active_video] [get_bd_pins rgb2dvi_0/vid_pVDE]
            connect_bd_net [get_bd_pins v_tc_0/hsync_out] [get_bd_pins rgb2dvi_0/vid_pHSync]
            connect_bd_net [get_bd_pins v_tc_0/vsync_out] [get_bd_pins rgb2dvi_0/vid_pVSync]
        } else {
            connect_bd_net [get_bd_pins v_tc_0/active_video_out] [get_bd_pins rgb2dvi_0/vid_pVDE]
            connect_bd_net [get_bd_pins v_tc_0/hsync_out] [get_bd_pins rgb2dvi_0/vid_pHSync]
            connect_bd_net [get_bd_pins v_tc_0/vsync_out] [get_bd_pins rgb2dvi_0/vid_pVSync]
        }
    }
} else {
    connect_bd_net [get_bd_pins v_axi4s_vid_out_0/vid_data] [get_bd_pins rgb2dvi_0/vid_pData]
    connect_bd_net [get_bd_pins v_axi4s_vid_out_0/vid_active_video] [get_bd_pins rgb2dvi_0/vid_pVDE]
    connect_bd_net [get_bd_pins v_axi4s_vid_out_0/vid_hsync] [get_bd_pins rgb2dvi_0/vid_pHSync]
    connect_bd_net [get_bd_pins v_axi4s_vid_out_0/vid_vsync] [get_bd_pins rgb2dvi_0/vid_pVSync]
}
connect_bd_net [get_bd_pins rgb2dvi_0/TMDS_Clk_p] $hcp; connect_bd_net [get_bd_pins rgb2dvi_0/TMDS_Clk_n] $hcn
connect_bd_net [get_bd_pins rgb2dvi_0/TMDS_Data_p] $hdp; connect_bd_net [get_bd_pins rgb2dvi_0/TMDS_Data_n] $hdn

# Status GPIOs: camera counters in one dual GPIO, full Video Out status and
# lock/underflow/overflow bits in a second dual GPIO.
foreach s {pclk_heartbeat overflow_sticky phase_error_sticky overflow_count completed_frame_count last_frame_lines last_frame_pixels min_line_pixels max_line_pixels odd_line_count last_frame_pclk_cycles} { connect_bd_net [get_bd_pins dvp_rgb565_rx_0/$s] [get_bd_pins camera_status_cdc_0/$s] }
connect_bd_net [get_bd_pins camera_status_cdc_0/status0] [get_bd_pins axi_gpio_status/gpio_io_i]
connect_bd_net [get_bd_pins camera_status_cdc_0/status1] [get_bd_pins axi_gpio_status/gpio2_io_i]
connect_bd_net [get_bd_pins camera_status_cdc_0/diag0] [get_bd_pins axi_gpio_camera_diag/gpio_io_i]
connect_bd_net [get_bd_pins camera_status_cdc_0/diag1] [get_bd_pins axi_gpio_camera_diag/gpio2_io_i]
if {$bram_live} {
    set zero_status [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:* xlconstant_video_status_zero]
    set_property -dict [list CONFIG.CONST_WIDTH {32} CONFIG.CONST_VAL {0}] $zero_status
    connect_bd_net [get_bd_pins xlconstant_video_status_zero/dout] [get_bd_pins axi_gpio_video_status/gpio_io_i] [get_bd_pins axi_gpio_video_status/gpio2_io_i]
} elseif {$hdmi_direct_raster} {
    connect_bd_net [get_bd_pins hdmi_vga_axis_raster_0/status0] [get_bd_pins axi_gpio_video_status/gpio_io_i]
    connect_bd_net [get_bd_pins hdmi_vga_axis_raster_0/status1] [get_bd_pins axi_gpio_video_status/gpio2_io_i]
} else {
    connect_bd_net [get_bd_pins hdmi_clocking_720p_0/ready] [get_bd_pins video_status_pack_0/clk_locked]
    connect_bd_net [get_bd_pins v_axi4s_vid_out_0/locked] [get_bd_pins video_status_pack_0/video_locked]
    connect_bd_net [get_bd_pins v_axi4s_vid_out_0/underflow] [get_bd_pins video_status_pack_0/underflow]
    connect_bd_net [get_bd_pins v_axi4s_vid_out_0/overflow] [get_bd_pins video_status_pack_0/overflow]
    connect_bd_net [get_bd_pins v_axi4s_vid_out_0/status] [get_bd_pins video_status_pack_0/video_status]
    connect_bd_net [get_bd_pins video_status_pack_0/status0] [get_bd_pins axi_gpio_video_status/gpio_io_i]
    connect_bd_net [get_bd_pins video_status_pack_0/status1] [get_bd_pins axi_gpio_video_status/gpio2_io_i]
}

connect_bd_intf_net [get_bd_intf_pins processing_system7_0/M_AXI_GP0] [get_bd_intf_pins axi_interconnect_ctrl/S00_AXI]
set slaves {axi_iic_0/S_AXI axi_gpio_0/S_AXI axi_gpio_status/S_AXI axi_gpio_video_status/S_AXI axi_vdma_0/S_AXI_LITE v_tc_0/ctrl axi_intc_0/s_axi axi_gpio_camera_diag/S_AXI}
if {$python_sixpanel} { lappend slaves axi_gpio_python_result/S_AXI }
if {$fpga_sixpanel} { lappend slaves sixpanel_accel_0/s_axi_control axi_gpio_menu/S_AXI }
if {$raster_mux_test} { lappend slaves axi_gpio_pixel_source/S_AXI }
if {$bram_live} { lappend slaves axi_bram_frame_ctrl/S_AXI }
if {$cnn_live} { lappend slaves axi_gpio_cnn_control/S_AXI axi_gpio_cnn_result/S_AXI axi_gpio_cnn_debug/S_AXI }
for {set i 0} {$i < [llength $slaves]} {incr i} { connect_bd_intf_net [get_bd_intf_pins [format "axi_interconnect_ctrl/M%02d_AXI" $i]] [get_bd_intf_pins [lindex $slaves $i]] }
connect_bd_intf_net [get_bd_intf_pins axi_vdma_0/M_AXI_MM2S] [get_bd_intf_pins axi_interconnect_mem/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_vdma_0/M_AXI_S2MM] [get_bd_intf_pins axi_interconnect_mem/S01_AXI]
if {$fpga_sixpanel} {
    foreach {master index} {m_axi_gmem_cam 2 m_axi_gmem_out 3 m_axi_gmem_hist 4 m_axi_gmem_work 5} {
        connect_bd_intf_net [get_bd_intf_pins sixpanel_accel_0/$master] [get_bd_intf_pins [format "axi_interconnect_mem/S%02d_AXI" $index]]
    }
    connect_bd_net [get_bd_pins sixpanel_accel_0/stable_tip_count] [get_bd_pins vision_tip_count_classifier_0/stable_tip_count]
    connect_bd_net [get_bd_pins sixpanel_accel_0/detector_valid] [get_bd_pins vision_tip_count_classifier_0/detector_valid]
    connect_bd_net [get_bd_pins sixpanel_accel_0/frame_done] [get_bd_pins vision_tip_count_classifier_0/frame_done]
    connect_bd_net [get_bd_pins vision_tip_count_classifier_0/result_valid] [get_bd_pins vision_result_button_latch_0/result_valid]
    connect_bd_net [get_bd_pins vision_tip_count_classifier_0/class_id] [get_bd_pins vision_result_button_latch_0/result_class]
}
connect_bd_intf_net [get_bd_intf_pins axi_interconnect_mem/M00_AXI] [get_bd_intf_pins processing_system7_0/S_AXI_HP0]

set sysclk [list processing_system7_0/M_AXI_GP0_ACLK processing_system7_0/S_AXI_HP0_ACLK axi_interconnect_ctrl/ACLK axi_interconnect_ctrl/S00_ACLK axi_interconnect_mem/ACLK axi_interconnect_mem/S00_ACLK axi_interconnect_mem/S01_ACLK axi_interconnect_mem/M00_ACLK axi_iic_0/s_axi_aclk axi_gpio_0/s_axi_aclk axi_gpio_status/s_axi_aclk axi_gpio_video_status/s_axi_aclk axi_gpio_camera_diag/s_axi_aclk axi_vdma_0/s_axi_lite_aclk axi_vdma_0/m_axi_mm2s_aclk axi_vdma_0/m_axi_s2mm_aclk axi_vdma_0/m_axis_mm2s_aclk axi_vdma_0/s_axis_s2mm_aclk axi_intc_0/s_axi_aclk axis_camera_fifo/m_axis_aclk v_tc_0/s_axi_aclk camera_status_cdc_0/sys_clk rst_sys_100m/slowest_sync_clk clk_wiz_720p/clk_in1]
if {$fpga_sixpanel} { lappend sysclk sixpanel_accel_0/ap_clk vision_tip_count_classifier_0/clk vision_result_button_latch_0/clk axi_gpio_menu/s_axi_aclk button_sync4_0/clk }
if {$fpga_sixpanel} { lappend sysclk axi_interconnect_mem/S02_ACLK axi_interconnect_mem/S03_ACLK axi_interconnect_mem/S04_ACLK axi_interconnect_mem/S05_ACLK }
if {$cnn_live} {
    lappend sysclk axis_cnn_camera_fifo/m_axis_aclk axi_gpio_cnn_control/s_axi_aclk axi_gpio_cnn_result/s_axi_aclk axi_gpio_cnn_debug/s_axi_aclk axis_object_locator_640x480_0/aclk axis_roi_crop_640x480_0/aclk axis_roi_frame_queue_0/aclk axis_rgb888_register_slice_0/aclk axis_pl_star_anise_cnn_0/aclk pl_cnn_result_box_latch_0/clk pl_cnn_result_box_cdc_0/src_clk
    if {$cnn_image_process} { lappend sysclk pl_cnn_button_trigger_0/clk }
}
if {$hdmi_direct_raster} {
    lappend sysclk axis_hdmi_fifo/s_axis_aclk
} else {
    lappend sysclk rgb565_to_rgb888_axis_0/aclk axis_letterbox_720p_0/aclk v_axi4s_vid_out_0/aclk
}
for {set i 0} {$i < 8} {incr i} { lappend sysclk [format "axi_interconnect_ctrl/M%02d_ACLK" $i] }
if {$python_sixpanel} { lappend sysclk axi_gpio_python_result/s_axi_aclk axi_interconnect_ctrl/M08_ACLK }
if {$fpga_sixpanel} { lappend sysclk axi_interconnect_ctrl/M08_ACLK axi_interconnect_ctrl/M09_ACLK }
if {$cnn_live} { for {set i 8} {$i < 11} {incr i} { lappend sysclk [format "axi_interconnect_ctrl/M%02d_ACLK" $i] } }
if {$shadow_compare || $fpga_mask_compare} { lappend sysclk axis_shadow_compare_rgb565_0/aclk }
if {$shadow_compare} { lappend sysclk pl_shadow_boost_button_0/clk }
if {$raster_mux_test} { lappend sysclk axi_gpio_pixel_source/s_axi_aclk axi_interconnect_ctrl/M08_ACLK }
if {$bram_live} { lappend sysclk axi_bram_frame_ctrl/s_axi_aclk axi_interconnect_ctrl/M08_ACLK }
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins $sysclk]
connect_bd_net [get_bd_pins clk_wiz_720p/clk_out1] [get_bd_pins hdmi_clocking_720p_0/raw_clk_5x]
connect_bd_net [get_bd_pins clk_wiz_720p/locked] [get_bd_pins hdmi_clocking_720p_0/mmcm_locked]
connect_bd_net [get_bd_pins hdmi_clocking_720p_0/pixel_clk] [get_bd_pins v_tc_0/clk] [get_bd_pins rgb2dvi_0/PixelClk] [get_bd_pins rst_video_720p/slowest_sync_clk]
if {$hdmi_direct_raster} {
    connect_bd_net [get_bd_pins hdmi_clocking_720p_0/pixel_clk] [get_bd_pins hdmi_vga_axis_raster_0/pixel_clk] [get_bd_pins axis_hdmi_fifo/m_axis_aclk]
    connect_bd_net [get_bd_pins hdmi_clocking_720p_0/ready] [get_bd_pins hdmi_vga_axis_raster_0/resetn]
    if {$cnn_live} {
        connect_bd_net [get_bd_pins hdmi_clocking_720p_0/pixel_clk] [get_bd_pins pl_cnn_result_box_cdc_0/dst_clk]
        connect_bd_net [get_bd_pins hdmi_clocking_720p_0/ready] [get_bd_pins pl_cnn_result_box_cdc_0/dst_resetn]
    }
} else {
    connect_bd_net [get_bd_pins hdmi_clocking_720p_0/pixel_clk] [get_bd_pins v_axi4s_vid_out_0/vid_io_out_clk]
}
if {$raster_mode} {
    connect_bd_net [get_bd_pins hdmi_clocking_720p_0/pixel_clk] [get_bd_pins hdmi_raster_test_0/pixel_clk]
}
if {$bram_live} {
    connect_bd_net [get_bd_pins hdmi_clocking_720p_0/pixel_clk] [get_bd_pins hdmi_bram_raster_0/pixel_clk] [get_bd_pins frame_bram/clkb]
    connect_bd_net [get_bd_pins hdmi_clocking_720p_0/ready] [get_bd_pins hdmi_bram_raster_0/resetn]
}
if {$raster_mux_test} {
    connect_bd_net [get_bd_pins hdmi_clocking_720p_0/pixel_clk] [get_bd_pins hdmi_pixel_mux_0/pixel_clk]
    connect_bd_net [get_bd_pins hdmi_clocking_720p_0/ready] [get_bd_pins hdmi_pixel_mux_0/resetn]
}
connect_bd_net [get_bd_pins hdmi_clocking_720p_0/serial_clk] [get_bd_pins rgb2dvi_0/SerialClk]
connect_bd_net [get_bd_pins camera_clock_buffer_0/cam_pclk_buf] [get_bd_pins rst_cam_pclk/slowest_sync_clk] [get_bd_pins axis_camera_fifo/s_axis_aclk]
if {$image_processing} { connect_bd_net [get_bd_pins camera_clock_buffer_0/cam_pclk_buf] [get_bd_pins axis_brightness_contrast_rgb565_0/aclk] }
if {$cnn_live} {
    if {$shadow_compare} {
        connect_bd_net [get_bd_pins camera_clock_buffer_0/cam_pclk_buf] [get_bd_pins axis_camera_raw_splitter/aclk] [get_bd_pins axis_cnn_camera_fifo/s_axis_aclk]
    } else {
        connect_bd_net [get_bd_pins camera_clock_buffer_0/cam_pclk_buf] [get_bd_pins axis_cnn_broadcaster/aclk] [get_bd_pins axis_cnn_camera_fifo/s_axis_aclk]
    }
    if {$cnn_image_process} { connect_bd_net [get_bd_pins rst_cam_pclk/peripheral_aresetn] [get_bd_pins pl_cnn_button_trigger_0/resetn] }
}

connect_bd_net [get_bd_pins processing_system7_0/FCLK_RESET0_N] [get_bd_pins rst_sys_100m/ext_reset_in] [get_bd_pins rst_cam_pclk/ext_reset_in]
connect_bd_net [get_bd_pins hdmi_clocking_720p_0/ready] [get_bd_pins rst_video_720p/ext_reset_in] [get_bd_pins rgb2dvi_0/aRst_n]
if {!$fpga_sixpanel} { connect_bd_net [get_bd_pins rst_video_720p/peripheral_reset] [get_bd_pins rgb2dvi_0/aRst] }
if {$raster_mode} {
    connect_bd_net [get_bd_pins hdmi_clocking_720p_0/ready] [get_bd_pins hdmi_raster_test_0/resetn]
}
set sysrst [list processing_system7_0/M_AXI_GP0_ARESETN processing_system7_0/S_AXI_HP0_ARESETN axi_interconnect_ctrl/ARESETN axi_interconnect_ctrl/S00_ARESETN axi_interconnect_mem/ARESETN axi_interconnect_mem/S00_ARESETN axi_interconnect_mem/S01_ARESETN axi_interconnect_mem/M00_ARESETN axi_iic_0/s_axi_aresetn axi_gpio_0/s_axi_aresetn axi_gpio_status/s_axi_aresetn axi_gpio_video_status/s_axi_aresetn axi_gpio_camera_diag/s_axi_aresetn axi_vdma_0/axi_resetn axi_intc_0/s_axi_aresetn axis_camera_fifo/m_axis_aresetn v_tc_0/s_axi_aresetn camera_status_cdc_0/sys_resetn]
if {$fpga_sixpanel} {
    lappend sysrst axi_interconnect_mem/S02_ARESETN axi_interconnect_mem/S03_ARESETN axi_interconnect_mem/S04_ARESETN axi_interconnect_mem/S05_ARESETN
    lappend sysrst axi_interconnect_ctrl/M08_ARESETN axi_interconnect_ctrl/M09_ARESETN sixpanel_accel_0/ap_rst_n vision_tip_count_classifier_0/resetn vision_result_button_latch_0/resetn axi_gpio_menu/s_axi_aresetn button_sync4_0/resetn
}
if {$cnn_live} {
    lappend sysrst axis_cnn_camera_fifo/m_axis_aresetn axi_gpio_cnn_control/s_axi_aresetn axi_gpio_cnn_result/s_axi_aresetn axi_gpio_cnn_debug/s_axi_aresetn axis_object_locator_640x480_0/aresetn axis_roi_crop_640x480_0/aresetn axis_roi_frame_queue_0/aresetn axis_rgb888_register_slice_0/aresetn axis_pl_star_anise_cnn_0/aresetn pl_cnn_result_box_latch_0/resetn pl_cnn_result_box_cdc_0/src_resetn
}
if {$hdmi_direct_raster} {
    lappend sysrst axis_hdmi_fifo/s_axis_aresetn
} else {
    lappend sysrst rgb565_to_rgb888_axis_0/aresetn axis_letterbox_720p_0/aresetn v_axi4s_vid_out_0/aresetn
}
for {set i 0} {$i < 8} {incr i} { lappend sysrst [format "axi_interconnect_ctrl/M%02d_ARESETN" $i] }
if {$python_sixpanel} { lappend sysrst axi_gpio_python_result/s_axi_aresetn axi_interconnect_ctrl/M08_ARESETN }
if {$cnn_live} { for {set i 8} {$i < 11} {incr i} { lappend sysrst [format "axi_interconnect_ctrl/M%02d_ARESETN" $i] } }
if {$shadow_compare || $fpga_mask_compare} { lappend sysrst axis_shadow_compare_rgb565_0/aresetn }
if {$shadow_compare} { lappend sysrst pl_shadow_boost_button_0/resetn }
if {$raster_mux_test} {
    lappend sysrst axi_gpio_pixel_source/s_axi_aresetn axi_interconnect_ctrl/M08_ARESETN
}
if {$bram_live} {
    lappend sysrst axi_bram_frame_ctrl/s_axi_aresetn axi_interconnect_ctrl/M08_ARESETN
}
connect_bd_net [get_bd_pins rst_sys_100m/peripheral_aresetn] [get_bd_pins $sysrst]
if {$image_processing} {
    connect_bd_net [get_bd_pins rst_cam_pclk/peripheral_aresetn] [get_bd_pins dvp_rgb565_rx_0/resetn] [get_bd_pins axis_camera_fifo/s_axis_aresetn] [get_bd_pins axis_brightness_contrast_rgb565_0/aresetn]
} else {
    connect_bd_net [get_bd_pins rst_cam_pclk/peripheral_aresetn] [get_bd_pins dvp_rgb565_rx_0/resetn] [get_bd_pins axis_camera_fifo/s_axis_aresetn]
}
if {$cnn_live} {
    if {$shadow_compare} {
        connect_bd_net [get_bd_pins rst_cam_pclk/peripheral_aresetn] [get_bd_pins axis_camera_raw_splitter/aresetn] [get_bd_pins axis_cnn_camera_fifo/s_axis_aresetn]
    } else {
        connect_bd_net [get_bd_pins rst_cam_pclk/peripheral_aresetn] [get_bd_pins axis_cnn_broadcaster/aresetn] [get_bd_pins axis_cnn_camera_fifo/s_axis_aresetn]
    }
}
connect_bd_net [get_bd_pins rst_video_720p/peripheral_aresetn] [get_bd_pins v_tc_0/resetn]
if {!$hdmi_direct_raster} {
    connect_bd_net [get_bd_pins rst_video_720p/peripheral_reset] [get_bd_pins v_axi4s_vid_out_0/vid_io_out_reset]
    connect_bd_net [get_bd_pins xlconstant_one/dout] [get_bd_pins v_axi4s_vid_out_0/aclken]
}
connect_bd_net [get_bd_pins xlconstant_one/dout] [get_bd_pins v_tc_0/clken] [get_bd_pins v_tc_0/s_axi_aclken]
connect_bd_net [get_bd_pins xlconstant_one/dout] [get_bd_pins v_tc_0/gen_clken]
connect_bd_net [get_bd_pins axi_vdma_0/mm2s_introut] [get_bd_pins xlconcat_irq/In0]
connect_bd_net [get_bd_pins axi_vdma_0/s2mm_introut] [get_bd_pins xlconcat_irq/In1]
connect_bd_net [get_bd_pins xlconcat_irq/dout] [get_bd_pins axi_intc_0/intr]
connect_bd_net [get_bd_pins axi_intc_0/irq] [get_bd_pins processing_system7_0/IRQ_F2P]

assign_bd_address
proc addr {name base} { set s [get_bd_addr_segs -of_objects [get_bd_addr_spaces processing_system7_0/Data] -filter "NAME =~ *${name}*"]; if {[llength $s] != 1} {error "Address segment not unique for $name"}; set_property offset $base $s; set_property range 64K $s }
if {$cnn_live} {
    addr axi_gpio_cnn_control 0x41300000
    addr axi_gpio_cnn_result 0x41310000
    addr axi_gpio_cnn_debug 0x41350000
    addr axi_gpio_status 0x41320000
    addr axi_gpio_video_status 0x41330000
    addr axi_gpio_camera_diag 0x41340000
    addr axi_gpio_status 0x41210000
    addr axi_gpio_video_status 0x41220000
    addr axi_gpio_camera_diag 0x41230000
} elseif {$raster_mux_test} {
    addr axi_gpio_pixel_source 0x41250000
    addr axi_gpio_camera_diag 0x41260000
    addr axi_gpio_status 0x41210000
    addr axi_gpio_camera_diag 0x41230000
    addr axi_gpio_video_status 0x41220000
} elseif {$python_sixpanel} {
    # Move the auto-assigned camera GPIO out of the way first, then assign
    # each AXI GPIO a unique slot without transient address overlap.
    addr axi_gpio_camera_diag 0x41250000
    addr axi_gpio_python_result 0x41260000
    addr axi_gpio_status 0x41210000
    addr axi_gpio_video_status 0x41220000
    addr axi_gpio_camera_diag 0x41230000
    addr axi_gpio_python_result 0x41240000
} elseif {$fpga_sixpanel} {
    # Keep the AXI interrupt controller out of the GPIO peripheral address window.
    addr axi_intc_0 0x41800000
    addr axi_gpio_status 0x41210000
    addr axi_gpio_video_status 0x41220000
    addr axi_gpio_camera_diag 0x41230000
    addr axi_gpio_menu 0x41270000
} else {
    addr axi_gpio_status 0x41210000
    addr axi_gpio_video_status 0x41220000
    addr axi_gpio_camera_diag 0x41230000
}
if {$bram_live} {
    set frame_seg [get_bd_addr_segs -of_objects [get_bd_addr_spaces processing_system7_0/Data] -filter {NAME =~ *axi_bram_frame_ctrl*}]
    if {[llength $frame_seg] != 1} { error "Frame BRAM address segment not unique" }
    set_property offset 0x40000000 $frame_seg
    set_property range 64K $frame_seg
}
addr axi_gpio_0 0x41200000
addr axi_iic_0 0x41600000; addr axi_intc_0 0x41800000; addr axi_vdma_0 0x43000000; addr v_tc_0 0x43C00000
if {$cnn_live} {
    addr axi_gpio_cnn_control 0x41250000
    addr axi_gpio_cnn_result 0x41260000
    addr axi_gpio_cnn_debug 0x41270000
}
validate_bd_design
save_bd_design
set bd [get_files ${design_name}.bd]; set_property synth_checkpoint_mode None $bd; generate_target all $bd
set wrapper [make_wrapper -files $bd -top]; add_files -norecurse $wrapper; set_property top system_wrapper [current_fileset]
add_files -fileset constrs_1 -norecurse [file join $root_dir constraints camera_hdmi_720p.xdc]
if {$image_processing} { add_files -fileset constrs_1 -norecurse [file join $root_dir constraints camera_image_processing.xdc] }
if {$cnn_live} {
    add_files -fileset constrs_1 -norecurse [file join $root_dir constraints pl_cnn_result_box_cdc.xdc]
}
if {$cnn_image_process} { add_files -fileset constrs_1 -norecurse [file join $root_dir constraints cnn_image_process.xdc] }
if {$shadow_compare} { add_files -fileset constrs_1 -norecurse [file join $root_dir constraints shadow_compare_buttons.xdc] }
if {$python_sixpanel} { add_files -fileset constrs_1 -norecurse [file join $root_dir constraints python_sixpanel_button.xdc] }
if {$fpga_sixpanel} {
    add_files -fileset constrs_1 -norecurse [file join $root_dir constraints fpga_sixpanel_buttons.xdc]
}
update_compile_order -fileset sources_1
puts "BD_OK"
if {$build_stage eq "bd" || $build_stage eq "vga_full_bd" || $build_stage eq "vga_full_neg_bd" || $build_stage eq "cnn_live_bd" || $build_stage eq "cnn_live_image_process_bd" || $build_stage eq "cnn_live_shadow_compare_bd" || $build_stage eq "cnn_live_sixpanel_bd" || $build_stage eq "fpga_mask_compare_bd" || $build_stage eq "python_sixpanel_bd" || $build_stage eq "fpga_sixpanel_bd"} { exit }
launch_runs synth_1 -jobs 1; wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} { error "Synthesis failed: [get_property STATUS [get_runs synth_1]]" }
if {$fpga_sixpanel} { set_property strategy Performance_Explore [get_runs impl_1] }
launch_runs impl_1 -to_step write_bitstream -jobs 1; wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} { error "Implementation failed: [get_property STATUS [get_runs impl_1]]" }
open_run impl_1
if {$raster_mux_test} {
    set mux_meta_d [get_pins -hier -filter {NAME =~ *hdmi_pixel_mux_0/inst/select_meta_reg/D}]
    if {[llength $mux_meta_d] != 1} { error "HDMI pixel mux CDC first-stage pin not found" }
    set_false_path -to $mux_meta_d
}
report_timing_summary -file [file join $delivery_dir timing_summary.rpt]
report_bus_skew -file [file join $delivery_dir bus_skew.rpt]
report_utilization -file [file join $delivery_dir utilization.rpt]
report_drc -file [file join $delivery_dir drc.rpt]
report_route_status -file [file join $delivery_dir route_status.rpt]
report_clock_networks -file [file join $delivery_dir clock_networks.rpt]
report_io -file [file join $delivery_dir io.rpt]

set timing_file [open [file join $delivery_dir timing_summary.rpt] r]
set timing_report [read $timing_file]
close $timing_file
set timing_re {^\s*(-?[0-9]+\.[0-9]+)\s+(-?[0-9]+\.[0-9]+)\s+([0-9]+)\s+([0-9]+)\s+(-?[0-9]+\.[0-9]+)\s+(-?[0-9]+\.[0-9]+)\s+([0-9]+)\s+([0-9]+)\s+(-?[0-9]+\.[0-9]+)\s+(-?[0-9]+\.[0-9]+)\s+([0-9]+)\s+([0-9]+)\s*$}
if {![regexp -line $timing_re $timing_report timing_row wns tns tns_failing tns_total whs ths ths_failing ths_total wpws tpws tpws_failing tpws_total]} {
    error "Signoff gate: unable to parse routed timing summary"
}
if {$wns <= 0 || $tns_failing != 0 || $tns < 0 || $whs <= 0 || $ths_failing != 0 || $ths < 0 || $wpws <= 0 || $tpws_failing != 0 || $tpws < 0} {
    error "Signoff gate: timing failed (WNS=$wns TNS=$tns WHS=$whs THS=$ths WPWS=$wpws TPWS=$tpws)"
}
set drc_errors [get_drc_violations -quiet -filter {SEVERITY == Error}]
if {[llength $drc_errors] != 0} {
    error "Signoff gate: [llength $drc_errors] DRC errors"
}
set route_file [open [file join $delivery_dir route_status.rpt] r]
set route_report [read $route_file]
close $route_file
if {![regexp {# of nets with routing errors[^:]*:\s*0\s*} $route_report]} {
    error "Signoff gate: routed design has routing errors"
}
set xdc_file [open [file join $root_dir constraints camera_hdmi_720p.xdc] r]
set xdc_text [read $xdc_file]
close $xdc_file
if {[regexp -nocase {CLOCK_DEDICATED_ROUTE\s+FALSE} $xdc_text]} {
    error "Signoff gate: CLOCK_DEDICATED_ROUTE FALSE is not allowed"
}
puts "SIGNOFF_OK WNS=$wns TNS=$tns WHS=$whs THS=$ths WPWS=$wpws TPWS=$tpws DRC=0 route_errors=0"

set bit [file join $project_dir ${project_name}.runs impl_1 system_wrapper.bit]
set hwh [file join $project_dir ${project_name}.gen sources_1 bd system hw_handoff system.hwh]
if {$build_stage eq "tx_test"} {
    set artifact_stem camera_hdmi_720p_tx_test
} elseif {$stream_data_test} {
    set artifact_stem camera_hdmi_720p_stream_data_test
} elseif {$stream_sync_test} {
    set artifact_stem camera_hdmi_720p_stream_sync_test
} elseif {$stream_de_test} {
    set artifact_stem camera_hdmi_720p_stream_de_test
} elseif {$build_stage eq "raster_test"} {
    set artifact_stem camera_hdmi_720p_raster_test
} elseif {$build_stage eq "raster_stream_test"} {
    set artifact_stem camera_hdmi_720p_raster_stream_test
} elseif {$build_stage eq "raster_stress_test"} {
    set artifact_stem camera_hdmi_720p_raster_stress_test
} elseif {$raster_mux_test} {
    set artifact_stem camera_hdmi_720p_raster_mux_test
} elseif {$bram_live} {
    set artifact_stem camera_hdmi_720p_bram_live
} elseif {$vga_full_neg} {
    set artifact_stem camera_hdmi_720p_vga_full_neg
} elseif {$vga_full} {
    set artifact_stem camera_hdmi_720p_vga_full
} elseif {$python_sixpanel} {
    set artifact_stem camera_hdmi_720p_python_sixpanel
} elseif {$fpga_sixpanel} {
    set artifact_stem camera_hdmi_720p_two_view_menu
} elseif {$fpga_mask_compare} {
    set artifact_stem camera_hdmi_720p_fpga_mask_compare
} elseif {$sixpanel_cnn} {
    set artifact_stem camera_hdmi_720p_sixpanel_cnn
} elseif {$shadow_compare} {
    set artifact_stem camera_hdmi_720p_shadow_compare
} elseif {$cnn_image_process} {
    set artifact_stem camera_hdmi_720p_cnn_image_process
} elseif {$image_processing} {
    set artifact_stem camera_hdmi_720p_image_process
} elseif {$cnn_blackguard} {
    set artifact_stem camera_hdmi_720p_cnn_blackguard
} elseif {$cnn_cropmatch} {
    set artifact_stem camera_hdmi_720p_cnn_cropmatch
} elseif {$cnn_live} {
    set artifact_stem camera_hdmi_720p_cnn_live
} else {
    set artifact_stem camera_hdmi_720p
}
foreach out [list $delivery_dir $overlay_dir] {
    file copy -force $bit [file join $out ${artifact_stem}.bit]
    file copy -force $hwh [file join $out ${artifact_stem}.hwh]
}
if {$fpga_mask_compare} {
    set delivery_rtl_files [list \
        [file join $root_dir src camera_clock_buffer.v] \
        [file join $root_dir src dvp_rgb565_rx.v] \
        [file join $root_dir src camera_status_cdc.v] \
        [file join $root_dir src axis_fpga_mask_compare_rgb565.v] \
        [file join $root_dir src hdmi_clocking_720p.v] \
        [file join $root_dir src hdmi_vga_axis_raster.v] \
        [file join $root_dir src rgb2dvi_compat.v] \
        [file join $root_dir ip digilent_rgb2dvi src SyncAsync.vhd] \
        [file join $root_dir ip digilent_rgb2dvi src SyncAsyncReset.vhd] \
        [file join $root_dir ip digilent_rgb2dvi src ClockGen.vhd] \
        [file join $root_dir ip digilent_rgb2dvi src DVI_Constants.vhd] \
        [file join $root_dir ip digilent_rgb2dvi src OutputSERDES.vhd] \
        [file join $root_dir ip digilent_rgb2dvi src TMDS_Encoder.vhd] \
        [file join $root_dir ip digilent_rgb2dvi src rgb2dvi.vhd]]
    set delivery_support_files [list \
        [file join $root_dir constraints camera_hdmi_720p.xdc] \
        [file join $root_dir scripts build_camera_hdmi_720p.tcl] \
        [file join $root_dir python ov5640_vga_720p_hdmi.py] \
        [file join $root_dir README.md] \
        [file join $root_dir HARDWARE_VALIDATION.md] \
        [file join $root_dir FPGA_MASK_COMPARE.md] \
        [file join $workspace STAR_ANISE_LIVE_VISION_HANDOFF_2026-10-25_FINAL board_source camera_web_stream.py] \
        [file join $workspace STAR_ANISE_LIVE_VISION_HANDOFF_2026-10-25_FINAL host live_vision_comparison.py] \
        [file join $workspace STAR_ANISE_LIVE_VISION_HANDOFF_2026-10-25_FINAL host shape_count_reference.py] \
        [file join $project_dir ${project_name}.xpr]]
} else {
    set delivery_rtl_files $rtl_files
    set delivery_support_files [list \
        [file join $root_dir constraints camera_hdmi_720p.xdc] \
        [file join $root_dir constraints camera_image_processing.xdc] \
        [file join $root_dir constraints cnn_image_process.xdc] \
        [file join $root_dir constraints shadow_compare_buttons.xdc] \
        [file join $root_dir constraints python_sixpanel_button.xdc] \
        [file join $root_dir constraints pl_cnn_result_box_cdc.xdc] \
        [file join $root_dir scripts build_camera_hdmi_720p.tcl] \
        [file join $root_dir python ov5640_vga_720p_hdmi.py] \
        [file join $root_dir python ov5640_vga_full_hdmi.py] \
        [file join $root_dir python hdmi_tx_test.py] \
        [file join $root_dir python hdmi_raster_test.py] \
        [file join $root_dir README.md] \
        [file join $root_dir HARDWARE_VALIDATION.md] \
        [file join $project_dir ${project_name}.xpr]]
}
if {$sixpanel_cnn} {
    lappend delivery_support_files \
        [file join $workspace camera_hdmi_720p_fpga_mask_compare_delivery board_vision_algorithms.py] \
        [file join $workspace camera_hdmi_720p_fpga_mask_compare_delivery board_hdmi_sixpanel_cnn.py] \
        [file join $workspace camera_hdmi_720p_fpga_mask_compare_delivery start_board_sixpanel_cnn.sh] \
        [file join $workspace camera_hdmi_720p_fpga_mask_compare_delivery FPGA_MASK_COMPARE.md]
}
if {$python_sixpanel} {
    lappend delivery_support_files \
        [file join $workspace camera_hdmi_720p_fpga_mask_compare_delivery board_vision_algorithms.py] \
        [file join $workspace camera_hdmi_720p_fpga_mask_compare_delivery board_hdmi_python_sixpanel.py] \
        [file join $workspace camera_hdmi_720p_fpga_mask_compare_delivery start_board_python_sixpanel.sh] \
        [file join $workspace camera_hdmi_720p_fpga_mask_compare_delivery PYTHON_SIXPANEL.md] \
        [file join $root_dir python ov5640_vga_720p_hdmi.py] \
        [file join $root_dir constraints python_sixpanel_button.xdc] \
        [file join $root_dir README.md]
}
if {$fpga_sixpanel} {
    set delivery_rtl_files [list \
        [file join $root_dir src camera_clock_buffer.v] \
        [file join $root_dir src dvp_rgb565_rx.v] \
        [file join $root_dir src camera_status_cdc.v] \
        [file join $root_dir src hdmi_clocking_720p.v] \
        [file join $workspace camera_hdmi_720p_python_sixpanel_delivery hdmi_vga_axis_raster.v] \
        [file join $workspace camera_hdmi_720p_fpga_sixpanel rtl vision_tip_count_classifier.v] \
        [file join $workspace camera_hdmi_720p_fpga_sixpanel rtl vision_result_button_latch.v] \
        [file join $root_dir src button_sync4.v]]
    set delivery_support_files [list \
        [file join $root_dir constraints camera_hdmi_720p.xdc] \
        [file join $root_dir constraints fpga_sixpanel_buttons.xdc] \
        [file join $workspace camera_hdmi_720p_fpga_sixpanel python board_fpga_two_view.py] \
        [file join $workspace camera_hdmi_720p_fpga_sixpanel python two_view_menu.py] \
        [file join $workspace camera_hdmi_720p_fpga_sixpanel python start_board_two_view.sh] \
        [file join $workspace camera_hdmi_720p_python_sixpanel_delivery ov5640_vga_720p_hdmi.py] \
        [file join $workspace camera_hdmi_720p_fpga_sixpanel hls sixpanel_accel.cpp] \
        [file join $workspace camera_hdmi_720p_fpga_sixpanel hls hls_config.cfg] \
        [file join $workspace camera_hdmi_720p_fpga_sixpanel hls build_hls.ps1] \
        [file join $workspace camera_hdmi_720p_fpga_sixpanel scripts package_rgb2dvi_compat.tcl] \
        [file join $workspace camera_hdmi_720p_fpga_sixpanel tests test_two_view_menu.py] \
        [file join $workspace camera_hdmi_720p_python_sixpanel_delivery build_camera_hdmi_720p.tcl] \
        [file join $root_dir src rgb2dvi_compat.v] \
        [file join $project_dir ${project_name}.xpr]]
    set local_ip_repo [file join $delivery_dir ip_repo]
    file mkdir $local_ip_repo
    file copy -force $hls_ip_root [file join $local_ip_repo sixpanel_accel]
    file copy -force $rgb_ip_root [file join $local_ip_repo rgb2dvi_compat]
}
foreach f $delivery_rtl_files { file copy -force $f $delivery_dir }
foreach f $delivery_support_files { if {[file exists $f]} { file copy -force $f $delivery_dir } }
if {$cnn_live} {
    set model_delivery [file join $delivery_dir model_int8]
    file mkdir $model_delivery
    foreach f $model_parameters { file copy -force $f $model_delivery }
    file copy -force [file join $cnn_artifact_dir manifest.json] $model_delivery
    set progress_doc [file join $root_dir pl_cnn PROGRESS_2026-10-02.md]
    if {[file exists $progress_doc]} { file copy -force $progress_doc $delivery_dir }
}
puts "BUILD_OK"

