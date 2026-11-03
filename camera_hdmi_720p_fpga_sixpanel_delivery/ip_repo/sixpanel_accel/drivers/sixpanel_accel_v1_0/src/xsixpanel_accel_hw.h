// ==============================================================
// Vitis HLS - High-Level Synthesis from C, C++ and OpenCL v2026.1 (64-bit)
// Tool Version Limit: 2026.06
// Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
// Copyright 2022-2026 Advanced Micro Devices, Inc. All Rights Reserved.
// 
// ==============================================================
// control
// 0x00 : Control signals
//        bit 0  - ap_start (Read/Write/COH)
//        bit 1  - ap_done (Read/COR)
//        bit 2  - ap_idle (Read)
//        bit 3  - ap_ready (Read/COR)
//        bit 7  - auto_restart (Read/Write)
//        bit 9  - interrupt (Read)
//        others - reserved
// 0x04 : Global Interrupt Enable Register
//        bit 0  - Global Interrupt Enable (Read/Write)
//        others - reserved
// 0x08 : IP Interrupt Enable Register (Read/Write)
//        bit 0 - enable ap_done interrupt (Read/Write)
//        bit 1 - enable ap_ready interrupt (Read/Write)
//        others - reserved
// 0x0c : IP Interrupt Status Register (Read/TOW)
//        bit 0 - ap_done (Read/TOW)
//        bit 1 - ap_ready (Read/TOW)
//        others - reserved
// 0x10 : Data signal of camera_frame
//        bit 31~0 - camera_frame[31:0] (Read/Write)
// 0x14 : Data signal of camera_frame
//        bit 31~0 - camera_frame[63:32] (Read/Write)
// 0x18 : reserved
// 0x1c : Data signal of mosaic_frame
//        bit 31~0 - mosaic_frame[31:0] (Read/Write)
// 0x20 : Data signal of mosaic_frame
//        bit 31~0 - mosaic_frame[63:32] (Read/Write)
// 0x24 : reserved
// 0x28 : Data signal of fill_history
//        bit 31~0 - fill_history[31:0] (Read/Write)
// 0x2c : Data signal of fill_history
//        bit 31~0 - fill_history[63:32] (Read/Write)
// 0x30 : reserved
// 0x34 : Data signal of panel_workspace
//        bit 31~0 - panel_workspace[31:0] (Read/Write)
// 0x38 : Data signal of panel_workspace
//        bit 31~0 - panel_workspace[63:32] (Read/Write)
// 0x3c : reserved
// 0x40 : Data signal of clear_history
//        bit 0  - clear_history[0] (Read/Write)
//        others - reserved
// 0x44 : reserved
// (SC = Self Clear, COR = Clear on Read, TOW = Toggle on Write, COH = Clear on Handshake)

#define XSIXPANEL_ACCEL_CONTROL_ADDR_AP_CTRL              0x00
#define XSIXPANEL_ACCEL_CONTROL_ADDR_GIE                  0x04
#define XSIXPANEL_ACCEL_CONTROL_ADDR_IER                  0x08
#define XSIXPANEL_ACCEL_CONTROL_ADDR_ISR                  0x0c
#define XSIXPANEL_ACCEL_CONTROL_ADDR_CAMERA_FRAME_DATA    0x10
#define XSIXPANEL_ACCEL_CONTROL_BITS_CAMERA_FRAME_DATA    64
#define XSIXPANEL_ACCEL_CONTROL_ADDR_MOSAIC_FRAME_DATA    0x1c
#define XSIXPANEL_ACCEL_CONTROL_BITS_MOSAIC_FRAME_DATA    64
#define XSIXPANEL_ACCEL_CONTROL_ADDR_FILL_HISTORY_DATA    0x28
#define XSIXPANEL_ACCEL_CONTROL_BITS_FILL_HISTORY_DATA    64
#define XSIXPANEL_ACCEL_CONTROL_ADDR_PANEL_WORKSPACE_DATA 0x34
#define XSIXPANEL_ACCEL_CONTROL_BITS_PANEL_WORKSPACE_DATA 64
#define XSIXPANEL_ACCEL_CONTROL_ADDR_CLEAR_HISTORY_DATA   0x40
#define XSIXPANEL_ACCEL_CONTROL_BITS_CLEAR_HISTORY_DATA   1

