cmake_minimum_required(VERSION 3.16)
project(u55c_template_harden_smoke_host LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

option(U55C_ENABLE_XRT "Build host runtime with XRT hardware support" ON)
option(U55C_ENABLE_CPU_REF "Build host runtime with legacy CPU-reference CNN path" ON)

add_executable(u55c_bench
  src/main.cpp
  src/runner.cpp
  src/csv_logger.cpp
  src/buffer_manager.cpp
)

target_include_directories(u55c_bench PRIVATE include)

target_compile_options(u55c_bench PRIVATE -Wall -Wextra -Wpedantic)

if(U55C_ENABLE_CPU_REF)
  set(LEGACY_CPU_REF_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../legacy_src/ece5775_final_proj/car_truck_accel/ecelinux")
  set(LEGACY_MLP_CPP "${LEGACY_CPU_REF_DIR}/mlp.cpp")
  set(LEGACY_LAYER_CPP "${LEGACY_CPU_REF_DIR}/layer.cpp")

  find_path(VITIS_AP_INCLUDE_DIR
    NAMES ap_int.h
    PATHS
      /tools/Xilinx/2025.1/Vitis/include
      /tools/Xilinx/Vitis/include
  )

  if(EXISTS "${LEGACY_MLP_CPP}" AND EXISTS "${LEGACY_LAYER_CPP}" AND VITIS_AP_INCLUDE_DIR)
    target_sources(u55c_bench PRIVATE
      "${LEGACY_MLP_CPP}"
      "${LEGACY_LAYER_CPP}"
    )
    target_include_directories(u55c_bench PRIVATE
      "${LEGACY_CPU_REF_DIR}"
      "${VITIS_AP_INCLUDE_DIR}"
    )
    target_compile_definitions(u55c_bench PRIVATE U55C_ENABLE_CPU_REF=1)
    message(STATUS "Building with CPU-reference support")
  else()
    message(WARNING "CPU-reference support disabled (missing legacy CNN sources or ap_int.h include path).")
  endif()
endif()

if(U55C_ENABLE_XRT)
  find_path(XRT_INCLUDE_DIR
    NAMES xrt/xrt_device.h
    PATHS
      /opt/xilinx/xrt/include
      /usr/include
      /usr/local/include
  )

  find_library(XRT_COREUTIL_LIBRARY
    NAMES xrt_coreutil
    PATHS
      /opt/xilinx/xrt/lib
      /usr/lib
      /usr/lib64
      /usr/lib/x86_64-linux-gnu
      /usr/local/lib
  )

  if(XRT_INCLUDE_DIR AND XRT_COREUTIL_LIBRARY)
    target_compile_definitions(u55c_bench PRIVATE U55C_ENABLE_XRT=1)
    target_include_directories(u55c_bench PRIVATE "${XRT_INCLUDE_DIR}")
    target_link_libraries(u55c_bench PRIVATE "${XRT_COREUTIL_LIBRARY}")
    message(STATUS "Building with XRT support")
  else()
    message(WARNING "XRT headers/libs not found. Building dry-run-only host executable.")
  endif()
endif()
