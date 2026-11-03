# ==============================================================
# Vitis HLS - High-Level Synthesis from C, C++ and OpenCL v2026.1 (64-bit)
# Tool Version Limit: 2026.06
# Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
# Copyright 2022-2026 Advanced Micro Devices, Inc. All Rights Reserved.
# 
# ==============================================================
cmake_minimum_required(VERSION 3.15)
project(sixpanel_accel)
find_package(common)
collector_create (PROJECT_LIB_SOURCES "${CMAKE_CURRENT_SOURCE_DIR}")
collect (PROJECT_LIB_SOURCES xsixpanel_accel.c)
collect (PROJECT_LIB_SOURCES xsixpanel_accel_sinit.c)
collect (PROJECT_LIB_SOURCES xsixpanel_accel_linux.c)
collect (PROJECT_LIB_SOURCES xsixpanel_accel_g.c)
collector_list (_sources PROJECT_LIB_SOURCES)
collector_create (PROJECT_LIB_HEADERS "${CMAKE_CURRENT_SOURCE_DIR}")
collect (PROJECT_LIB_HEADERS xsixpanel_accel.h)
collect (PROJECT_LIB_HEADERS xsixpanel_accel_hw.h)
collector_list (_headers PROJECT_LIB_HEADERS)
file(COPY ${_headers} DESTINATION ${CMAKE_BINARY_DIR}/include)
include_directories(${CMAKE_BINARY_DIR}/include)
add_library(sixpanel_accel STATIC ${_sources})
set_target_properties(sixpanel_accel PROPERTIES LINKER_LANGUAGE C)

