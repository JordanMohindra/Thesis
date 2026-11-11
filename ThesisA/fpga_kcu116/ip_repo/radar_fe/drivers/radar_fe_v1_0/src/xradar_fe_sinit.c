// ==============================================================
// Vitis HLS - High-Level Synthesis from C, C++ and OpenCL v2026.1 (64-bit)
// Tool Version Limit: 2026.06
// Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
// Copyright 2022-2026 Advanced Micro Devices, Inc. All Rights Reserved.
// 
// ==============================================================
#ifndef __linux__

#include "xstatus.h"
#ifdef SDT
#include "xparameters.h"
#endif
#include "xradar_fe.h"

extern XRadar_fe_Config XRadar_fe_ConfigTable[];

#ifdef SDT
XRadar_fe_Config *XRadar_fe_LookupConfig(UINTPTR BaseAddress) {
	XRadar_fe_Config *ConfigPtr = NULL;

	int Index;

	for (Index = (u32)0x0; XRadar_fe_ConfigTable[Index].Name != NULL; Index++) {
		if (!BaseAddress || XRadar_fe_ConfigTable[Index].Control_BaseAddress == BaseAddress) {
			ConfigPtr = &XRadar_fe_ConfigTable[Index];
			break;
		}
	}

	return ConfigPtr;
}

int XRadar_fe_Initialize(XRadar_fe *InstancePtr, UINTPTR BaseAddress) {
	XRadar_fe_Config *ConfigPtr;

	Xil_AssertNonvoid(InstancePtr != NULL);

	ConfigPtr = XRadar_fe_LookupConfig(BaseAddress);
	if (ConfigPtr == NULL) {
		InstancePtr->IsReady = 0;
		return (XST_DEVICE_NOT_FOUND);
	}

	return XRadar_fe_CfgInitialize(InstancePtr, ConfigPtr);
}
#else
XRadar_fe_Config *XRadar_fe_LookupConfig(u16 DeviceId) {
	XRadar_fe_Config *ConfigPtr = NULL;

	int Index;

	for (Index = 0; Index < XPAR_XRADAR_FE_NUM_INSTANCES; Index++) {
		if (XRadar_fe_ConfigTable[Index].DeviceId == DeviceId) {
			ConfigPtr = &XRadar_fe_ConfigTable[Index];
			break;
		}
	}

	return ConfigPtr;
}

int XRadar_fe_Initialize(XRadar_fe *InstancePtr, u16 DeviceId) {
	XRadar_fe_Config *ConfigPtr;

	Xil_AssertNonvoid(InstancePtr != NULL);

	ConfigPtr = XRadar_fe_LookupConfig(DeviceId);
	if (ConfigPtr == NULL) {
		InstancePtr->IsReady = 0;
		return (XST_DEVICE_NOT_FOUND);
	}

	return XRadar_fe_CfgInitialize(InstancePtr, ConfigPtr);
}
#endif

#endif

