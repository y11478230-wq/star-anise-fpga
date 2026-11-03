// ==============================================================
// Vitis HLS - High-Level Synthesis from C, C++ and OpenCL v2026.1 (64-bit)
// Tool Version Limit: 2026.06
// Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
// Copyright 2022-2026 Advanced Micro Devices, Inc. All Rights Reserved.
// 
// ==============================================================
/***************************** Include Files *********************************/
#include "xsixpanel_accel.h"

/************************** Function Implementation *************************/
#ifndef __linux__
int XSixpanel_accel_CfgInitialize(XSixpanel_accel *InstancePtr, XSixpanel_accel_Config *ConfigPtr) {
    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(ConfigPtr != NULL);

    InstancePtr->Control_BaseAddress = ConfigPtr->Control_BaseAddress;
    InstancePtr->IsReady = XIL_COMPONENT_IS_READY;

    return XST_SUCCESS;
}
#endif

void XSixpanel_accel_Start(XSixpanel_accel *InstancePtr) {
    u32 Data;

    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XSixpanel_accel_ReadReg(InstancePtr->Control_BaseAddress, XSIXPANEL_ACCEL_CONTROL_ADDR_AP_CTRL) & 0x80;
    XSixpanel_accel_WriteReg(InstancePtr->Control_BaseAddress, XSIXPANEL_ACCEL_CONTROL_ADDR_AP_CTRL, Data | 0x01);
}

u32 XSixpanel_accel_IsDone(XSixpanel_accel *InstancePtr) {
    u32 Data;

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XSixpanel_accel_ReadReg(InstancePtr->Control_BaseAddress, XSIXPANEL_ACCEL_CONTROL_ADDR_AP_CTRL);
    return (Data >> 1) & 0x1;
}

u32 XSixpanel_accel_IsIdle(XSixpanel_accel *InstancePtr) {
    u32 Data;

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XSixpanel_accel_ReadReg(InstancePtr->Control_BaseAddress, XSIXPANEL_ACCEL_CONTROL_ADDR_AP_CTRL);
    return (Data >> 2) & 0x1;
}

u32 XSixpanel_accel_IsReady(XSixpanel_accel *InstancePtr) {
    u32 Data;

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XSixpanel_accel_ReadReg(InstancePtr->Control_BaseAddress, XSIXPANEL_ACCEL_CONTROL_ADDR_AP_CTRL);
    // check ap_start to see if the pcore is ready for next input
    return !(Data & 0x1);
}

void XSixpanel_accel_EnableAutoRestart(XSixpanel_accel *InstancePtr) {
    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    XSixpanel_accel_WriteReg(InstancePtr->Control_BaseAddress, XSIXPANEL_ACCEL_CONTROL_ADDR_AP_CTRL, 0x80);
}

void XSixpanel_accel_DisableAutoRestart(XSixpanel_accel *InstancePtr) {
    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    XSixpanel_accel_WriteReg(InstancePtr->Control_BaseAddress, XSIXPANEL_ACCEL_CONTROL_ADDR_AP_CTRL, 0);
}

void XSixpanel_accel_Set_camera_frame(XSixpanel_accel *InstancePtr, u64 Data) {
    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    XSixpanel_accel_WriteReg(InstancePtr->Control_BaseAddress, XSIXPANEL_ACCEL_CONTROL_ADDR_CAMERA_FRAME_DATA, (u32)(Data));
    XSixpanel_accel_WriteReg(InstancePtr->Control_BaseAddress, XSIXPANEL_ACCEL_CONTROL_ADDR_CAMERA_FRAME_DATA + 4, (u32)(Data >> 32));
}

u64 XSixpanel_accel_Get_camera_frame(XSixpanel_accel *InstancePtr) {
    u64 Data;

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XSixpanel_accel_ReadReg(InstancePtr->Control_BaseAddress, XSIXPANEL_ACCEL_CONTROL_ADDR_CAMERA_FRAME_DATA);
    Data += (u64)XSixpanel_accel_ReadReg(InstancePtr->Control_BaseAddress, XSIXPANEL_ACCEL_CONTROL_ADDR_CAMERA_FRAME_DATA + 4) << 32;
    return Data;
}

void XSixpanel_accel_Set_mosaic_frame(XSixpanel_accel *InstancePtr, u64 Data) {
    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    XSixpanel_accel_WriteReg(InstancePtr->Control_BaseAddress, XSIXPANEL_ACCEL_CONTROL_ADDR_MOSAIC_FRAME_DATA, (u32)(Data));
    XSixpanel_accel_WriteReg(InstancePtr->Control_BaseAddress, XSIXPANEL_ACCEL_CONTROL_ADDR_MOSAIC_FRAME_DATA + 4, (u32)(Data >> 32));
}

u64 XSixpanel_accel_Get_mosaic_frame(XSixpanel_accel *InstancePtr) {
    u64 Data;

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XSixpanel_accel_ReadReg(InstancePtr->Control_BaseAddress, XSIXPANEL_ACCEL_CONTROL_ADDR_MOSAIC_FRAME_DATA);
    Data += (u64)XSixpanel_accel_ReadReg(InstancePtr->Control_BaseAddress, XSIXPANEL_ACCEL_CONTROL_ADDR_MOSAIC_FRAME_DATA + 4) << 32;
    return Data;
}

void XSixpanel_accel_Set_fill_history(XSixpanel_accel *InstancePtr, u64 Data) {
    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    XSixpanel_accel_WriteReg(InstancePtr->Control_BaseAddress, XSIXPANEL_ACCEL_CONTROL_ADDR_FILL_HISTORY_DATA, (u32)(Data));
    XSixpanel_accel_WriteReg(InstancePtr->Control_BaseAddress, XSIXPANEL_ACCEL_CONTROL_ADDR_FILL_HISTORY_DATA + 4, (u32)(Data >> 32));
}

u64 XSixpanel_accel_Get_fill_history(XSixpanel_accel *InstancePtr) {
    u64 Data;

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XSixpanel_accel_ReadReg(InstancePtr->Control_BaseAddress, XSIXPANEL_ACCEL_CONTROL_ADDR_FILL_HISTORY_DATA);
    Data += (u64)XSixpanel_accel_ReadReg(InstancePtr->Control_BaseAddress, XSIXPANEL_ACCEL_CONTROL_ADDR_FILL_HISTORY_DATA + 4) << 32;
    return Data;
}

void XSixpanel_accel_Set_panel_workspace(XSixpanel_accel *InstancePtr, u64 Data) {
    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    XSixpanel_accel_WriteReg(InstancePtr->Control_BaseAddress, XSIXPANEL_ACCEL_CONTROL_ADDR_PANEL_WORKSPACE_DATA, (u32)(Data));
    XSixpanel_accel_WriteReg(InstancePtr->Control_BaseAddress, XSIXPANEL_ACCEL_CONTROL_ADDR_PANEL_WORKSPACE_DATA + 4, (u32)(Data >> 32));
}

u64 XSixpanel_accel_Get_panel_workspace(XSixpanel_accel *InstancePtr) {
    u64 Data;

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XSixpanel_accel_ReadReg(InstancePtr->Control_BaseAddress, XSIXPANEL_ACCEL_CONTROL_ADDR_PANEL_WORKSPACE_DATA);
    Data += (u64)XSixpanel_accel_ReadReg(InstancePtr->Control_BaseAddress, XSIXPANEL_ACCEL_CONTROL_ADDR_PANEL_WORKSPACE_DATA + 4) << 32;
    return Data;
}

void XSixpanel_accel_Set_clear_history(XSixpanel_accel *InstancePtr, u32 Data) {
    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    XSixpanel_accel_WriteReg(InstancePtr->Control_BaseAddress, XSIXPANEL_ACCEL_CONTROL_ADDR_CLEAR_HISTORY_DATA, Data);
}

u32 XSixpanel_accel_Get_clear_history(XSixpanel_accel *InstancePtr) {
    u32 Data;

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XSixpanel_accel_ReadReg(InstancePtr->Control_BaseAddress, XSIXPANEL_ACCEL_CONTROL_ADDR_CLEAR_HISTORY_DATA);
    return Data;
}

void XSixpanel_accel_InterruptGlobalEnable(XSixpanel_accel *InstancePtr) {
    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    XSixpanel_accel_WriteReg(InstancePtr->Control_BaseAddress, XSIXPANEL_ACCEL_CONTROL_ADDR_GIE, 1);
}

void XSixpanel_accel_InterruptGlobalDisable(XSixpanel_accel *InstancePtr) {
    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    XSixpanel_accel_WriteReg(InstancePtr->Control_BaseAddress, XSIXPANEL_ACCEL_CONTROL_ADDR_GIE, 0);
}

void XSixpanel_accel_InterruptEnable(XSixpanel_accel *InstancePtr, u32 Mask) {
    u32 Register;

    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Register =  XSixpanel_accel_ReadReg(InstancePtr->Control_BaseAddress, XSIXPANEL_ACCEL_CONTROL_ADDR_IER);
    XSixpanel_accel_WriteReg(InstancePtr->Control_BaseAddress, XSIXPANEL_ACCEL_CONTROL_ADDR_IER, Register | Mask);
}

void XSixpanel_accel_InterruptDisable(XSixpanel_accel *InstancePtr, u32 Mask) {
    u32 Register;

    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Register =  XSixpanel_accel_ReadReg(InstancePtr->Control_BaseAddress, XSIXPANEL_ACCEL_CONTROL_ADDR_IER);
    XSixpanel_accel_WriteReg(InstancePtr->Control_BaseAddress, XSIXPANEL_ACCEL_CONTROL_ADDR_IER, Register & (~Mask));
}

void XSixpanel_accel_InterruptClear(XSixpanel_accel *InstancePtr, u32 Mask) {
    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    XSixpanel_accel_WriteReg(InstancePtr->Control_BaseAddress, XSIXPANEL_ACCEL_CONTROL_ADDR_ISR, Mask);
}

u32 XSixpanel_accel_InterruptGetEnabled(XSixpanel_accel *InstancePtr) {
    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    return XSixpanel_accel_ReadReg(InstancePtr->Control_BaseAddress, XSIXPANEL_ACCEL_CONTROL_ADDR_IER);
}

u32 XSixpanel_accel_InterruptGetStatus(XSixpanel_accel *InstancePtr) {
    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    return XSixpanel_accel_ReadReg(InstancePtr->Control_BaseAddress, XSIXPANEL_ACCEL_CONTROL_ADDR_ISR);
}

