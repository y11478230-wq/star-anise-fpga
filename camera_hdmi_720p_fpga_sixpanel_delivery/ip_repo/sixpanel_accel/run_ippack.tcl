# ==============================================================
# Vitis HLS - High-Level Synthesis from C, C++ and OpenCL v2026.1 (64-bit)
# Tool Version Limit: 2026.06
# Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
# Copyright 2022-2026 Advanced Micro Devices, Inc. All Rights Reserved.
# 
# ==============================================================
source -notrace "E:/Vivado/2026.1/Vitis/common/scripts/ipxhls.tcl"
set ip_out_dir "E:/sixpanel_build/hls/vitis_workspace_filled_edges_20261028/sixpanel_accel/sixpanel_accel/hls/impl/ip"
set data_file "E:/sixpanel_build/hls/vitis_workspace_filled_edges_20261028/sixpanel_accel/sixpanel_accel/hls/hls_data.json"
set src_dir [file dir $data_file]
set ip_types {vitis sysgen}
set ippack_opts_dict {}
if { [catch {::ipx::utils::package_hls_ip $ip_out_dir $data_file $ip_types $src_dir $ippack_opts_dict} res] } {
  puts "Caught error:\n$::errorInfo"
  error $res
}
