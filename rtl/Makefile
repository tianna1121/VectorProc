# 
# Copyright 2011-2012 Jeff Bush
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#     http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# 

ENABLE_SDRAM=1
ENABLE_SMP=0	

CORE_SRCS=	core/instruction_fetch_stage.v \
			core/strand_select_stage.v \
			core/decode_stage.v \
			core/execute_stage.v \
			core/memory_access_stage.v \
			core/writeback_stage.v \
			core/pipeline.v \
			core/vector_register_file.v \
			core/scalar_register_file.v \
			core/vector_bypass_unit.v \
			core/rollback_controller.v \
			core/multi_cycle_alu.v \
			core/single_cycle_alu.v \
			core/fp_adder_stage1.v \
			core/fp_adder_stage2.v \
			core/fp_adder_stage3.v \
			core/fp_multiplier_stage1.v \
			core/fp_normalize.v \
			core/integer_multiplier.v \
			core/lane_select_mux.v \
			core/fp_reciprocal_estimate.v \
			core/reciprocal_rom.v \
			core/l1_cache.v \
			core/l1_cache_tag.v \
			core/cache_lru.v \
			core/store_buffer.v \
			core/sync_fifo.v \
			core/arbiter.v \
			core/strand_fsm.v \
			core/core.v \
			core/load_miss_queue.v \
			core/mask_unit.v \
			core/l2req_arbiter_mux.v \
			core/assert_false.v \
			core/control_registers.v \
			core/l2_cache.v \
			core/l2_cache_arb.v \
			core/l2_cache_response.v \
			core/l2_cache_bus_interface.v \
			core/l2_cache_tag.v \
			core/l2_cache_dir.v \
			core/l2_cache_read.v \
			core/l2_cache_write.v \
			core/l2_cache_pending_miss.v \
			core/sram_1r1w.v \
			core/cache_valid_array.v \
			core/endian_swapper.v
	
SIMULATOR_SRCS=testbench/simulator_top.v \
			core/performance_counters.v \
			$(CORE_SRCS)

FPGA_SIM_SRCS=testbench/fpga_sim.v \
			testbench/sim_jtagloader.v \
			fpga/fpga_axi_mem.v \
			fpga/fpga_top.v \
			fpga/uart.v \
			$(CORE_SRCS)

INCLUDES=core/defines.v

IVFLAGS=-Wall -Winfloop -civerilog.cmd -Wno-sensitivity-entire-array -Icore

ifeq ($(ENABLE_SMP), 1)
	IVFLAGS += -DENABLE_CORE1
endif

ifeq ($(ENABLE_SDRAM), 1)
	IVFLAGS += -DENABLE_SDRAM
	SIMULATOR_SRCS += core/sdram_controller.v testbench/sim_sdram.v
else
	SIMULATOR_SRCS += fpga/fpga_axi_mem.v
endif

sim.vvp: $(SIMULATOR_SRCS) $(INCLUDES) Makefile
	iverilog -o $@ $(IVFLAGS) $(SIMULATOR_SRCS)

# Simulates FPGA environment.  Is missing many inspection features necessary for
# cosimulation, etc.
fpga-sim.vvp: $(FPGA_SIM_SRCS) $(INCLUDES) Makefile
	iverilog -o $@ $(IVFLAGS) $(FPGA_SIM_SRCS)

# Expands AUTOWIRE/AUTOINST/etc. Requires emacs and verilog-mode module installed.
autos: $(SIMULATOR_SRCS)
	emacs --batch $(SIMULATOR_SRCS) -f verilog-batch-auto -f save-buffer
	emacs --batch fpga/* -f verilog-batch-auto -f save-buffer
	emacs --batch testbench/fpga_sim.v  -f verilog-batch-auto -f save-buffer
	
# Print warnings if Verilator is installed
lint: $(SIMULATOR_SRCS)
	-verilator --lint-only core/core.v -Wall -Icore -Wno-ASSIGNDLY 
	-verilator --lint-only core/l2_cache.v -Wall -Icore -Wno-ASSIGNDLY 

clean:
	rm -f sim.vvp
