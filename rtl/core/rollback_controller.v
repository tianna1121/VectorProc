// 
// Copyright 2011-2012 Jeff Bush
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

//
// Reconcile rollback requests from multiple stages and strands.
//
// When a rollback occurs, we squash instructions that are earlier in the 
// pipeline and are from the same strand.  Note that multiple rollbacks
// for the same strand may occur in the same cycle.  In this situation, the
// rollback for the oldest PC (one that is farthest down the pipeline) takes
// precedence.
//
// A rollback request does not trigger a squash of the instruction in the stage
// that requested the  rollback. The requesting stage must do that.  This is mainly 
// because of call instructions, which must propagate to the writeback stage to 
// update the link register.
//
// The ex_strandx notation may be confusing:
//    ex_strand refers to the instruction coming out of the execute stage
//    ex_strandn refers to an instruction in the intermediate stage of the 
//	  multi-cycle pipeline, which may be a *later* instruction that ex_strand because
//    the mux acts as a bypass.
//

module rollback_controller(
	input [1:0]					ss_strand,
	input						ex_rollback_request, 	// execute
	input [31:0]				ex_rollback_pc, 
	input [1:0]					ds_strand,
	input [1:0]					ex_strand,				// strand coming out of ex stage
	input [1:0]					ex_strand1,				// strands in multi-cycle pipeline
	input [1:0]					ex_strand2,
	input [1:0]					ex_strand3,
	input						wb_rollback_request, 	// writeback
	input						wb_retry,
	input [31:0]				wb_rollback_pc,
	input [31:0]				ma_strided_offset,
	input [3:0]					ma_reg_lane_select,
	input [1:0]					ma_strand,
	input						wb_suspend_request,
	output 						squash_ds,		// decode
	output 						squash_ex0,		// execute
	output 						squash_ex1,
	output 						squash_ex2,
	output 						squash_ex3,
	output 						squash_ma,		// memory access
	output 						rb_rollback_strand0,
	output reg[31:0]			rb_rollback_pc0,
	output reg[31:0]			rollback_strided_offset0,
	output reg[3:0]				rollback_reg_lane0,
	output reg					suspend_strand0,
	output 						rb_retry_strand0,
	output 						rb_rollback_strand1,
	output reg[31:0]			rb_rollback_pc1,
	output reg[31:0]			rollback_strided_offset1,
	output reg[3:0]				rollback_reg_lane1,
	output reg					suspend_strand1,
	output 						rb_retry_strand1,
	output 						rb_rollback_strand2,
	output reg[31:0]			rb_rollback_pc2,
	output reg[31:0]			rollback_strided_offset2,
	output reg[3:0]				rollback_reg_lane2,
	output reg					suspend_strand2,
	output 						rb_retry_strand2,
	output 						rb_rollback_strand3,
	output reg[31:0]			rb_rollback_pc3,
	output reg[31:0]			rollback_strided_offset3,
	output reg[3:0]				rollback_reg_lane3,
	output reg					suspend_strand3,
	output 						rb_retry_strand3);

	wire rollback_wb_str0 = wb_rollback_request && ma_strand == 0;
	wire rollback_wb_str1 = wb_rollback_request && ma_strand == 1;
	wire rollback_wb_str2 = wb_rollback_request && ma_strand == 2;
	wire rollback_wb_str3 = wb_rollback_request && ma_strand == 3;
	wire rollback_ex_str0 = ex_rollback_request && ds_strand == 0;
	wire rollback_ex_str1 = ex_rollback_request && ds_strand == 1;
	wire rollback_ex_str2 = ex_rollback_request && ds_strand == 2;
	wire rollback_ex_str3 = ex_rollback_request && ds_strand == 3;

	assign rb_rollback_strand0 = rollback_wb_str0
		|| rollback_ex_str0;
	assign rb_rollback_strand1 = rollback_wb_str1
		|| rollback_ex_str1;
	assign rb_rollback_strand2 = rollback_wb_str2
		|| rollback_ex_str2;
	assign rb_rollback_strand3 = rollback_wb_str3
		|| rollback_ex_str3;

	assign rb_retry_strand0 = rollback_wb_str0 && wb_retry;
	assign rb_retry_strand1 = rollback_wb_str1 && wb_retry;
	assign rb_retry_strand2 = rollback_wb_str2 && wb_retry;
	assign rb_retry_strand3 = rollback_wb_str3 && wb_retry;

	assign squash_ma = (rollback_wb_str0 && ex_strand == 0)
		|| (rollback_wb_str1 && ex_strand == 1)
		|| (rollback_wb_str2 && ex_strand == 2)
		|| (rollback_wb_str3 && ex_strand == 3);
	assign squash_ex0 = (rollback_wb_str0 && ds_strand == 0)
		|| (rollback_wb_str1 && ds_strand == 1)
		|| (rollback_wb_str2 && ds_strand == 2)
		|| (rollback_wb_str3 && ds_strand == 3);
	assign squash_ex1 = (rollback_wb_str0 && ex_strand1 == 0)
		|| (rollback_wb_str1 && ex_strand1 == 1)
		|| (rollback_wb_str2 && ex_strand1 == 2)
		|| (rollback_wb_str3 && ex_strand1 == 3);
	assign squash_ex2 = (rollback_wb_str0 && ex_strand2 == 0)
		|| (rollback_wb_str1 && ex_strand2 == 1)
		|| (rollback_wb_str2 && ex_strand2 == 2)
		|| (rollback_wb_str3 && ex_strand2 == 3);
	assign squash_ex3 = (rollback_wb_str0 && ex_strand3 == 0)
		|| (rollback_wb_str1 && ex_strand3 == 1)
		|| (rollback_wb_str2 && ex_strand3 == 2)
		|| (rollback_wb_str3 && ex_strand3 == 3);
	assign squash_ds = (rb_rollback_strand0 && ss_strand == 0)
		|| (rb_rollback_strand1 && ss_strand == 1)
		|| (rb_rollback_strand2 && ss_strand == 2)
		|| (rb_rollback_strand3 && ss_strand == 3);
		
	always @*
	begin
		if (rollback_wb_str0)
		begin
			rb_rollback_pc0 = wb_rollback_pc;
			rollback_strided_offset0 = ma_strided_offset;
			rollback_reg_lane0 = ma_reg_lane_select;
			suspend_strand0 = wb_suspend_request;
		end
		else /* if (rollback_ex_str0) or don't care */
		begin
			rb_rollback_pc0 = ex_rollback_pc;
			rollback_strided_offset0 = 0;
			rollback_reg_lane0 = 0;
			suspend_strand0 = 0;
		end
	end

	always @*
	begin
		if (rollback_wb_str1)
		begin
			rb_rollback_pc1 = wb_rollback_pc;
			rollback_strided_offset1 = ma_strided_offset;
			rollback_reg_lane1 = ma_reg_lane_select;
			suspend_strand1 = wb_suspend_request;
		end
		else /* if (rollback_ex_str1) or don't care */
		begin
			rb_rollback_pc1 = ex_rollback_pc;
			rollback_strided_offset1 = 0;
			rollback_reg_lane1 = 0;
			suspend_strand1 = 0;
		end
	end

	always @*
	begin
		if (rollback_wb_str2)
		begin
			rb_rollback_pc2 = wb_rollback_pc;
			rollback_strided_offset2 = ma_strided_offset;
			rollback_reg_lane2 = ma_reg_lane_select;
			suspend_strand2 = wb_suspend_request;
		end
		else /* if (rollback_ex_str2) or don't care */
		begin
			rb_rollback_pc2 = ex_rollback_pc;
			rollback_strided_offset2 = 0;
			rollback_reg_lane2 = 0;
			suspend_strand2 = 0;
		end
	end

	always @*
	begin
		if (rollback_wb_str3)
		begin
			rb_rollback_pc3 = wb_rollback_pc;
			rollback_strided_offset3 = ma_strided_offset;
			rollback_reg_lane3 = ma_reg_lane_select;
			suspend_strand3 = wb_suspend_request;
		end
		else /* if (rollback_ex_str3) or don't care */
		begin
			rb_rollback_pc3 = ex_rollback_pc;
			rollback_strided_offset3 = 0;
			rollback_reg_lane3 = 0;
			suspend_strand3 = 0;
		end
	end
endmodule
