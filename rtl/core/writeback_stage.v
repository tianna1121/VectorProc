// 
// Copyright 2011-2013 Jeff Bush
// 
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
// 
//     http://www.apache.org/licenses/LICENSE-2.0
// 
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
// 

`include "defines.v"

//
// Instruction pipeline writeback stage
//  - Handle aligning memory reads
//  - Determine what the source of the register writeback should be
//  - Control signals to control commit of values back to the register file
//  - PC loads from memory are handled here.
//  - Detect and dispatch exceptions.  We defer processing exceptions from earlier
//    stages until here to ensure the exceptions are precise. Specifically, 
//    we want to make sure they won't be rolled back because of a PC load branch
//    or cache miss.
//

module writeback_stage(
	input					clk,
	input					reset,

	// From data cache
	input 					dcache_hit,
	input [511:0]			data_from_dcache,
	input					dcache_load_collision,
	input 					stbuf_rollback,

	// From memory access stage
	input [31:0]			ma_instruction,
	input [31:0]			ma_pc,
	input [6:0]				ma_writeback_reg,
	input					ma_enable_scalar_writeback,	
	input					ma_enable_vector_writeback,	
	input [15:0]			ma_mask,
	input 					ma_was_load,
	input					ma_alignment_fault,
	input [511:0]			ma_result,
	input [3:0]				ma_reg_lane_select,
	input [3:0]				ma_cache_lane_select,
	input [1:0]				ma_strand,
	input					ma_was_io,
	input [31:0]			ma_io_response,

	// To register file	
	output reg				wb_enable_scalar_writeback,	
	output reg				wb_enable_vector_writeback,	
	output reg[6:0]			wb_writeback_reg,
	output reg[511:0]		wb_writeback_value,
	output reg[15:0]		wb_writeback_mask,
	
	// To/From control registers
	input [31:0]			cr_exception_handler_address,
	output 					wb_latch_fault,
	output [31:0]			wb_fault_pc,
	output [1:0]			wb_fault_strand,
	
	// To rollback controller
	output reg				wb_rollback_request,
	output reg[31:0]		wb_rollback_pc,
	output 					wb_suspend_request,
	output					wb_retry,
	
	// Performance counter events
	output					pc_event_instruction_retire);

	reg[511:0]				writeback_value_nxt;
	reg[15:0]				mask_nxt;
	reg[31:0]				aligned_read_value;
	reg[15:0]				half_aligned;
	reg[7:0]				byte_aligned;
	wire[31:0]				lane_value;

	wire is_fmt_c = ma_instruction[31:30] == 2'b10;
	wire is_load = is_fmt_c && ma_instruction[29];
	wire[3:0] c_op_type = ma_instruction[28:25];
	wire is_control_register_transfer = is_fmt_c
		&& c_op_type == 4'b0110;
	wire cache_miss = !dcache_hit && ma_was_load && !dcache_load_collision;

	always @*
	begin
		if (ma_alignment_fault)
		begin
			wb_rollback_pc = cr_exception_handler_address;
			wb_rollback_request = 1;
		end
		else if (ma_was_io)
		begin
			// Ignore cache hit/miss signals if this was a device IO transaction
			wb_rollback_pc = 0;
			wb_rollback_request = 0;
		end
		else if (dcache_load_collision)
		begin
			// Data came in one cycle too late.  Roll back and retry.
			wb_rollback_pc = ma_pc - 4;
			wb_rollback_request = 1;
		end
		else if (cache_miss || stbuf_rollback)
		begin
			// Data cache read miss or store buffer rollback (full or synchronized store)
			wb_rollback_pc = ma_pc - 4;
			wb_rollback_request = 1;
		end
		else if (ma_enable_scalar_writeback && ma_writeback_reg[4:0] == 31 && is_load)
		begin
			// A load has occurred to PC, branch to that address
			// Note that we checked for a cache miss *before* we checked
			// this case, otherwise we'd just jump to address zero.
			wb_rollback_pc = aligned_read_value;
			wb_rollback_request = 1;
		end
		else
		begin
			wb_rollback_pc = 0;
			wb_rollback_request = 0;
		end
	end
	
	assign wb_latch_fault = ma_alignment_fault;
	assign wb_fault_pc = ma_pc;
	assign wb_fault_strand = ma_strand;
	
	assign wb_suspend_request = cache_miss || stbuf_rollback;
	assign wb_retry = dcache_load_collision; 

	lane_select_mux #(.ASCENDING_INDEX(1)) lsm(
		.value_i(data_from_dcache),
		.value_o(lane_value),
		.lane_select_i(ma_cache_lane_select));
	
	wire[511:0] endian_twiddled_data;
	endian_swapper dcache_endian_swapper[15:0](
		.inval(data_from_dcache),
		.endian_twiddled_data(endian_twiddled_data));

	// Byte aligner.  ma_result still contains the effective address,
	// so use that to determine where the data will appear.
	always @*
	begin
		case (ma_result[1:0])
			2'b00: byte_aligned = lane_value[31:24];
			2'b01: byte_aligned = lane_value[23:16];
			2'b10: byte_aligned = lane_value[15:8];
			2'b11: byte_aligned = lane_value[7:0];
		endcase
	end

	// Halfword aligner.  Same as above.
	always @*
	begin
		case (ma_result[1])
			1'b0: half_aligned = { lane_value[23:16], lane_value[31:24] };
			1'b1: half_aligned = { lane_value[7:0], lane_value[15:8] };
		endcase
	end

	// Pick the proper aligned result and sign extend as requested.
	always @*
	begin
		case (c_op_type)		// Load width
			// Unsigned byte
			`MEM_B: aligned_read_value = { 24'b0, byte_aligned };	

			// Signed byte
			`MEM_BX: aligned_read_value = { {24{byte_aligned[7]}}, byte_aligned }; 

			// Unsigned half-word
			`MEM_S: aligned_read_value = { 16'b0, half_aligned };

			// Signed half-word
			`MEM_SX: aligned_read_value = { {16{half_aligned[15]}}, half_aligned };

			// Word (100) and others
			default: aligned_read_value = { lane_value[7:0], lane_value[15:8],
				lane_value[23:16], lane_value[31:24] };	
		endcase
	end

	always @*
	begin
		if (ma_instruction[31:25] == 7'b1000101)
		begin
			// Synchronized store.  Success value comes back from cache
			writeback_value_nxt = data_from_dcache;
			mask_nxt = 16'hffff;
		end
		else if (is_load && !is_control_register_transfer)
		begin
			// Load result
			if (ma_was_io)
			begin
				writeback_value_nxt = {16{ma_io_response}}; // Non-cache load
				mask_nxt = 16'hffff;
			end
			else if (c_op_type[3] == 0 && c_op_type != `MEM_BLOCK)
			begin
				writeback_value_nxt = {16{aligned_read_value}}; // Scalar Load
				mask_nxt = 16'hffff;
			end
			else
			begin
				if (c_op_type == `MEM_BLOCK || c_op_type == `MEM_BLOCK_M
					|| c_op_type == `MEM_BLOCK_IM)
				begin
					// Block load
					mask_nxt = ma_mask;	
					writeback_value_nxt = endian_twiddled_data;	// Vector Load
				end
				else 
				begin
					// Strided or gather load
					// Grab the appropriate lane.
					writeback_value_nxt = {16{aligned_read_value}};
					mask_nxt = (1 << ma_reg_lane_select) & ma_mask;	// sg or strided
				end
			end
		end
		else
		begin
			// Arithmetic expression
			writeback_value_nxt = ma_result;
			mask_nxt = ma_mask;
		end
	end
	
	assign pc_event_instruction_retire = !wb_rollback_request && ma_instruction != `NOP;

	always @(posedge clk, posedge reset)
	begin
		if (reset)
		begin
			/*AUTORESET*/
			// Beginning of autoreset for uninitialized flops
			wb_enable_scalar_writeback <= 1'h0;
			wb_enable_vector_writeback <= 1'h0;
			wb_writeback_mask <= 16'h0;
			wb_writeback_reg <= 7'h0;
			wb_writeback_value <= 512'h0;
			// End of automatics
		end
		else
		begin
			wb_writeback_value 			<= writeback_value_nxt;
			wb_writeback_mask 			<= mask_nxt;
			wb_writeback_reg 			<= ma_writeback_reg;
			wb_enable_scalar_writeback 	<= ma_enable_scalar_writeback && !wb_rollback_request;	
			wb_enable_vector_writeback 	<= ma_enable_vector_writeback && !wb_rollback_request;
		end
	end
endmodule
