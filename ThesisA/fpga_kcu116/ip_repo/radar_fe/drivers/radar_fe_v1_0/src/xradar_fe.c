// ==============================================================
// Vitis HLS - High-Level Synthesis from C, C++ and OpenCL v2026.1 (64-bit)
// Tool Version Limit: 2026.06
// Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
// Copyright 2022-2026 Advanced Micro Devices, Inc. All Rights Reserved.
// 
// ==============================================================
/***************************** Include Files *********************************/
#include "xradar_fe.h"

/************************** Function Implementation *************************/
#ifndef __linux__
int XRadar_fe_CfgInitialize(XRadar_fe *InstancePtr, XRadar_fe_Config *ConfigPtr) {
    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(ConfigPtr != NULL);

    InstancePtr->Control_BaseAddress = ConfigPtr->Control_BaseAddress;
    InstancePtr->IsReady = XIL_COMPONENT_IS_READY;

    return XST_SUCCESS;
}
#endif

void XRadar_fe_Start(XRadar_fe *InstancePtr) {
    u32 Data;

    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XRadar_fe_ReadReg(InstancePtr->Control_BaseAddress, XRADAR_FE_CONTROL_ADDR_AP_CTRL) & 0x80;
    XRadar_fe_WriteReg(InstancePtr->Control_BaseAddress, XRADAR_FE_CONTROL_ADDR_AP_CTRL, Data | 0x01);
}

u32 XRadar_fe_IsDone(XRadar_fe *InstancePtr) {
    u32 Data;

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XRadar_fe_ReadReg(InstancePtr->Control_BaseAddress, XRADAR_FE_CONTROL_ADDR_AP_CTRL);
    return (Data >> 1) & 0x1;
}

u32 XRadar_fe_IsIdle(XRadar_fe *InstancePtr) {
    u32 Data;

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XRadar_fe_ReadReg(InstancePtr->Control_BaseAddress, XRADAR_FE_CONTROL_ADDR_AP_CTRL);
    return (Data >> 2) & 0x1;
}

u32 XRadar_fe_IsReady(XRadar_fe *InstancePtr) {
    u32 Data;

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XRadar_fe_ReadReg(InstancePtr->Control_BaseAddress, XRADAR_FE_CONTROL_ADDR_AP_CTRL);
    // check ap_start to see if the pcore is ready for next input
    return !(Data & 0x1);
}

void XRadar_fe_EnableAutoRestart(XRadar_fe *InstancePtr) {
    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    XRadar_fe_WriteReg(InstancePtr->Control_BaseAddress, XRADAR_FE_CONTROL_ADDR_AP_CTRL, 0x80);
}

void XRadar_fe_DisableAutoRestart(XRadar_fe *InstancePtr) {
    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    XRadar_fe_WriteReg(InstancePtr->Control_BaseAddress, XRADAR_FE_CONTROL_ADDR_AP_CTRL, 0);
}

void XRadar_fe_Set_nRamps(XRadar_fe *InstancePtr, u32 Data) {
    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    XRadar_fe_WriteReg(InstancePtr->Control_BaseAddress, XRADAR_FE_CONTROL_ADDR_NRAMPS_DATA, Data);
}

u32 XRadar_fe_Get_nRamps(XRadar_fe *InstancePtr) {
    u32 Data;

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Data = XRadar_fe_ReadReg(InstancePtr->Control_BaseAddress, XRADAR_FE_CONTROL_ADDR_NRAMPS_DATA);
    return Data;
}

void XRadar_fe_InterruptGlobalEnable(XRadar_fe *InstancePtr) {
    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    XRadar_fe_WriteReg(InstancePtr->Control_BaseAddress, XRADAR_FE_CONTROL_ADDR_GIE, 1);
}

void XRadar_fe_InterruptGlobalDisable(XRadar_fe *InstancePtr) {
    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    XRadar_fe_WriteReg(InstancePtr->Control_BaseAddress, XRADAR_FE_CONTROL_ADDR_GIE, 0);
}

void XRadar_fe_InterruptEnable(XRadar_fe *InstancePtr, u32 Mask) {
    u32 Register;

    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Register =  XRadar_fe_ReadReg(InstancePtr->Control_BaseAddress, XRADAR_FE_CONTROL_ADDR_IER);
    XRadar_fe_WriteReg(InstancePtr->Control_BaseAddress, XRADAR_FE_CONTROL_ADDR_IER, Register | Mask);
}

void XRadar_fe_InterruptDisable(XRadar_fe *InstancePtr, u32 Mask) {
    u32 Register;

    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    Register =  XRadar_fe_ReadReg(InstancePtr->Control_BaseAddress, XRADAR_FE_CONTROL_ADDR_IER);
    XRadar_fe_WriteReg(InstancePtr->Control_BaseAddress, XRADAR_FE_CONTROL_ADDR_IER, Register & (~Mask));
}

void XRadar_fe_InterruptClear(XRadar_fe *InstancePtr, u32 Mask) {
    Xil_AssertVoid(InstancePtr != NULL);
    Xil_AssertVoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    XRadar_fe_WriteReg(InstancePtr->Control_BaseAddress, XRADAR_FE_CONTROL_ADDR_ISR, Mask);
}

u32 XRadar_fe_InterruptGetEnabled(XRadar_fe *InstancePtr) {
    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    return XRadar_fe_ReadReg(InstancePtr->Control_BaseAddress, XRADAR_FE_CONTROL_ADDR_IER);
}

u32 XRadar_fe_InterruptGetStatus(XRadar_fe *InstancePtr) {
    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);

    return XRadar_fe_ReadReg(InstancePtr->Control_BaseAddress, XRADAR_FE_CONTROL_ADDR_ISR);
}

