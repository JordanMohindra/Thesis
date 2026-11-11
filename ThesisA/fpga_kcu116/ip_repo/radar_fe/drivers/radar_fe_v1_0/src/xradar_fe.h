// ==============================================================
// Vitis HLS - High-Level Synthesis from C, C++ and OpenCL v2026.1 (64-bit)
// Tool Version Limit: 2026.06
// Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
// Copyright 2022-2026 Advanced Micro Devices, Inc. All Rights Reserved.
// 
// ==============================================================
#ifndef XRADAR_FE_H
#define XRADAR_FE_H

#ifdef __cplusplus
extern "C" {
#endif

/***************************** Include Files *********************************/
#ifndef __linux__
#include "xil_types.h"
#include "xil_assert.h"
#include "xstatus.h"
#include "xil_io.h"
#else
#include <stdint.h>
#include <assert.h>
#include <dirent.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
#include <stddef.h>
#endif
#include "xradar_fe_hw.h"

/**************************** Type Definitions ******************************/
#ifdef __linux__
typedef uint8_t u8;
typedef uint16_t u16;
typedef uint32_t u32;
typedef uint64_t u64;
#else
typedef struct {
#ifdef SDT
    char *Name;
#else
    u16 DeviceId;
#endif
    u64 Control_BaseAddress;
} XRadar_fe_Config;
#endif

typedef struct {
    u64 Control_BaseAddress;
    u32 IsReady;
} XRadar_fe;

typedef u32 word_type;

/***************** Macros (Inline Functions) Definitions *********************/
#ifndef __linux__
#define XRadar_fe_WriteReg(BaseAddress, RegOffset, Data) \
    Xil_Out32((BaseAddress) + (RegOffset), (u32)(Data))
#define XRadar_fe_ReadReg(BaseAddress, RegOffset) \
    Xil_In32((BaseAddress) + (RegOffset))
#else
#define XRadar_fe_WriteReg(BaseAddress, RegOffset, Data) \
    *(volatile u32*)((BaseAddress) + (RegOffset)) = (u32)(Data)
#define XRadar_fe_ReadReg(BaseAddress, RegOffset) \
    *(volatile u32*)((BaseAddress) + (RegOffset))

#define Xil_AssertVoid(expr)    assert(expr)
#define Xil_AssertNonvoid(expr) assert(expr)

#define XST_SUCCESS             0
#define XST_DEVICE_NOT_FOUND    2
#define XST_OPEN_DEVICE_FAILED  3
#define XIL_COMPONENT_IS_READY  1
#endif

/************************** Function Prototypes *****************************/
#ifndef __linux__
#ifdef SDT
int XRadar_fe_Initialize(XRadar_fe *InstancePtr, UINTPTR BaseAddress);
XRadar_fe_Config* XRadar_fe_LookupConfig(UINTPTR BaseAddress);
#else
int XRadar_fe_Initialize(XRadar_fe *InstancePtr, u16 DeviceId);
XRadar_fe_Config* XRadar_fe_LookupConfig(u16 DeviceId);
#endif
int XRadar_fe_CfgInitialize(XRadar_fe *InstancePtr, XRadar_fe_Config *ConfigPtr);
#else
int XRadar_fe_Initialize(XRadar_fe *InstancePtr, const char* InstanceName);
int XRadar_fe_Release(XRadar_fe *InstancePtr);
#endif

void XRadar_fe_Start(XRadar_fe *InstancePtr);
u32 XRadar_fe_IsDone(XRadar_fe *InstancePtr);
u32 XRadar_fe_IsIdle(XRadar_fe *InstancePtr);
u32 XRadar_fe_IsReady(XRadar_fe *InstancePtr);
void XRadar_fe_EnableAutoRestart(XRadar_fe *InstancePtr);
void XRadar_fe_DisableAutoRestart(XRadar_fe *InstancePtr);

void XRadar_fe_Set_nRamps(XRadar_fe *InstancePtr, u32 Data);
u32 XRadar_fe_Get_nRamps(XRadar_fe *InstancePtr);

void XRadar_fe_InterruptGlobalEnable(XRadar_fe *InstancePtr);
void XRadar_fe_InterruptGlobalDisable(XRadar_fe *InstancePtr);
void XRadar_fe_InterruptEnable(XRadar_fe *InstancePtr, u32 Mask);
void XRadar_fe_InterruptDisable(XRadar_fe *InstancePtr, u32 Mask);
void XRadar_fe_InterruptClear(XRadar_fe *InstancePtr, u32 Mask);
u32 XRadar_fe_InterruptGetEnabled(XRadar_fe *InstancePtr);
u32 XRadar_fe_InterruptGetStatus(XRadar_fe *InstancePtr);

#ifdef __cplusplus
}
#endif

#endif
