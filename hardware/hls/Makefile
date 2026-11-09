SHELL := /usr/bin/env bash

ROOT_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/../..)
BUILD_DIR ?= $(ROOT_DIR)/build/hardware/$(TARGET)
PROJECT_NAME ?= $(notdir $(ROOT_DIR))
KERNEL_NAME ?= vector_add
TARGET ?= hw
PLATFORM ?= xilinx_u55c_gen3x16_xdma_3_202210_1
LEGACY_ECE5775_DIR := $(ROOT_DIR)/legacy_src/ece5775_final_proj/car_truck_accel/ecelinux

ifeq ($(KERNEL_NAME),mlp_u55c)
SRC := $(LEGACY_ECE5775_DIR)/mlp_u55c_kernel.cpp
EXTRA_SRCS := \
	$(LEGACY_ECE5775_DIR)/mlp.cpp \
	$(LEGACY_ECE5775_DIR)/layer.cpp
else
SRC := $(ROOT_DIR)/hardware/hls/src/$(KERNEL_NAME).cpp
EXTRA_SRCS :=
endif

SRCS := $(SRC) $(EXTRA_SRCS)
XO := $(BUILD_DIR)/$(KERNEL_NAME).xo
XCLBIN := $(BUILD_DIR)/$(KERNEL_NAME).xclbin
DASHBOARD_XCLBIN_DIR ?= $(HOME)/.local/share/fpga-dashboard-web/artifacts/xclbin
DASHBOARD_XCLBIN := $(DASHBOARD_XCLBIN_DIR)/$(PROJECT_NAME)_$(KERNEL_NAME)_$(TARGET).xclbin
DASHBOARD_LTX := $(DASHBOARD_XCLBIN:.xclbin=.ltx)
LINK_HOOK_SCRIPT := $(ROOT_DIR)/hardware/hls/scripts/u55c_clk_metadata_adapter_workaround.tcl
LINK_HOOK_ARGS :=
HLS_JOBS ?= 0
VIVADO_SYNTH_JOBS ?= 0
VIVADO_IMPL_JOBS ?= 0

VPP_HLS_JOB_ARGS :=
ifneq ($(strip $(HLS_JOBS)),0)
VPP_HLS_JOB_ARGS += --hls.jobs $(HLS_JOBS)
endif

VPP_LINK_JOB_ARGS :=
ifneq ($(strip $(VIVADO_SYNTH_JOBS)),0)
VPP_LINK_JOB_ARGS += --vivado.synth.jobs $(VIVADO_SYNTH_JOBS)
endif
ifneq ($(strip $(VIVADO_IMPL_JOBS)),0)
VPP_LINK_JOB_ARGS += --vivado.impl.jobs $(VIVADO_IMPL_JOBS)
endif

ifeq ($(TARGET),hw)
LINK_HOOK_ARGS += --linkhook.custom "postSysLink,$(LINK_HOOK_SCRIPT)"
endif

.PHONY: all xo xclbin publish clean

all: xclbin

xo: $(XO)

xclbin: $(XCLBIN)

$(XO): $(SRCS)
	@mkdir -p $(BUILD_DIR)
	v++ -c -t $(TARGET) --platform $(PLATFORM) $(VPP_HLS_JOB_ARGS) -k $(KERNEL_NAME) $^ -o $@

$(XCLBIN): $(XO)
	v++ -l -t $(TARGET) --platform $(PLATFORM) $(VPP_LINK_JOB_ARGS) $(LINK_HOOK_ARGS) $< -o $@
	@$(MAKE) publish TARGET=$(TARGET) KERNEL_NAME=$(KERNEL_NAME) PLATFORM=$(PLATFORM)

publish:
	@test -f "$(XCLBIN)" || { echo "ERROR: xclbin not found: $(XCLBIN)"; exit 1; }
	@mkdir -p "$(DASHBOARD_XCLBIN_DIR)"
	cp -f "$(XCLBIN)" "$(DASHBOARD_XCLBIN)"
	@if [[ -f "$(BUILD_DIR)/$(KERNEL_NAME).ltx" ]]; then cp -f "$(BUILD_DIR)/$(KERNEL_NAME).ltx" "$(DASHBOARD_LTX)"; fi
	@echo "Published dashboard artifact: $(DASHBOARD_XCLBIN)"

clean:
	rm -rf $(ROOT_DIR)/build/hardware
