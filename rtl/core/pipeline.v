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
// Contains the 6 CPU pipeline stages (instruction fetch, strand select,
// decode, execute, memory access, writeback), and the vector and scalar
// register files.
//

module pipeline
	#(parameter			CORE_ID = 30'd0)

	(input				clk,
	input				reset,
	output				halt_o,
	
	// To/from instruction cache
	output [31:0]		icache_addr,
	input [31:0]		icache_data,
	output				icache_request,
	input				icache_hit,
	output [1:0]		icache_req_strand,
	input [3:0]			icache_load_complete_strands,
	input				icache_load_collision,

	// Non-cacheable memory signals
	output				io_write_en,
	output				io_read_en,
	output[31:0]		io_address,
	output[31:0]		io_write_data,
	input [31:0]		io_read_data,

	// To L1 data cache/store buffer
	output [25:0]		dcache_addr,
	output				dcache_load,
	output				dcache_req_sync,
	output				dcache_store,
	output				dcache_flush,
	output				dcache_stbar,
	output				dcache_dinvalidate,
	output				dcache_iinvalidate,
	output [1:0]		dcache_req_strand,
	output [63:0]		dcache_store_mask,
	output [511:0]		data_to_dcache,

	// From L1 data cache/store buffer
	input				dcache_hit,
	input				stbuf_rollback,
	input [511:0]		data_from_dcache,
	input [3:0]			dcache_resume_strands,
	input				dcache_load_collision,

	// Performance counter events
	output [3:0]			pc_event_raw_wait,
	output [3:0]			pc_event_dcache_wait,
	output [3:0]			pc_event_icache_wait,
	output					pc_event_mispredicted_branch,
	output					pc_event_instruction_issue,
	output					pc_event_instruction_retire,
	output					pc_event_uncond_branch,
	output					pc_event_cond_branch_taken,
	output					pc_event_cond_branch_not_taken);
	
	reg	rf_enable_vector_writeback;
	reg	rf_enable_scalar_writeback;
	reg[6:0] rf_writeback_reg;		// One cycle after writeback
	reg[511:0] rf_writeback_value;
	reg[15:0] rf_writeback_mask;
	
	/*AUTOWIRE*/
	// Beginning of automatic wires (for undeclared instantiated-module outputs)
	wire [31:0]	cr_exception_handler_address;// From control_registers of control_registers.v
	wire [31:0]	cr_read_value;		// From control_registers of control_registers.v
	wire [3:0]	cr_strand_enable;	// From control_registers of control_registers.v
	wire [5:0]	ds_alu_op;		// From decode_stage of decode_stage.v
	wire		ds_branch_predicted;	// From decode_stage of decode_stage.v
	wire		ds_enable_scalar_writeback;// From decode_stage of decode_stage.v
	wire		ds_enable_vector_writeback;// From decode_stage of decode_stage.v
	wire [31:0]	ds_immediate_value;	// From decode_stage of decode_stage.v
	wire [31:0]	ds_instruction;		// From decode_stage of decode_stage.v
	wire		ds_long_latency;	// From decode_stage of decode_stage.v
	wire [2:0]	ds_mask_src;		// From decode_stage of decode_stage.v
	wire		ds_op1_is_vector;	// From decode_stage of decode_stage.v
	wire [1:0]	ds_op2_src;		// From decode_stage of decode_stage.v
	wire [31:0]	ds_pc;			// From decode_stage of decode_stage.v
	wire [3:0]	ds_reg_lane_select;	// From decode_stage of decode_stage.v
	wire [6:0]	ds_scalar_sel1;		// From decode_stage of decode_stage.v
	wire [6:0]	ds_scalar_sel1_l;	// From decode_stage of decode_stage.v
	wire [6:0]	ds_scalar_sel2;		// From decode_stage of decode_stage.v
	wire [6:0]	ds_scalar_sel2_l;	// From decode_stage of decode_stage.v
	wire		ds_store_value_is_vector;// From decode_stage of decode_stage.v
	wire [1:0]	ds_strand;		// From decode_stage of decode_stage.v
	wire [31:0]	ds_strided_offset;	// From decode_stage of decode_stage.v
	wire [6:0]	ds_vector_sel1;		// From decode_stage of decode_stage.v
	wire [6:0]	ds_vector_sel1_l;	// From decode_stage of decode_stage.v
	wire [6:0]	ds_vector_sel2;		// From decode_stage of decode_stage.v
	wire [6:0]	ds_vector_sel2_l;	// From decode_stage of decode_stage.v
	wire [6:0]	ds_writeback_reg;	// From decode_stage of decode_stage.v
	wire [31:0]	ex_base_addr;		// From execute_stage of execute_stage.v
	wire		ex_enable_scalar_writeback;// From execute_stage of execute_stage.v
	wire		ex_enable_vector_writeback;// From execute_stage of execute_stage.v
	wire [31:0]	ex_instruction;		// From execute_stage of execute_stage.v
	wire [15:0]	ex_mask;		// From execute_stage of execute_stage.v
	wire [31:0]	ex_pc;			// From execute_stage of execute_stage.v
	wire [3:0]	ex_reg_lane_select;	// From execute_stage of execute_stage.v
	wire [511:0]	ex_result;		// From execute_stage of execute_stage.v
	wire [31:0]	ex_rollback_pc;		// From execute_stage of execute_stage.v
	wire		ex_rollback_request;	// From execute_stage of execute_stage.v
	wire [511:0]	ex_store_value;		// From execute_stage of execute_stage.v
	wire [1:0]	ex_strand;		// From execute_stage of execute_stage.v
	wire [1:0]	ex_strand1;		// From execute_stage of execute_stage.v
	wire [1:0]	ex_strand2;		// From execute_stage of execute_stage.v
	wire [1:0]	ex_strand3;		// From execute_stage of execute_stage.v
	wire [31:0]	ex_strided_offset;	// From execute_stage of execute_stage.v
	wire [6:0]	ex_writeback_reg;	// From execute_stage of execute_stage.v
	wire		if_branch_predicted0;	// From instruction_fetch_stage of instruction_fetch_stage.v
	wire		if_branch_predicted1;	// From instruction_fetch_stage of instruction_fetch_stage.v
	wire		if_branch_predicted2;	// From instruction_fetch_stage of instruction_fetch_stage.v
	wire		if_branch_predicted3;	// From instruction_fetch_stage of instruction_fetch_stage.v
	wire [31:0]	if_instruction0;	// From instruction_fetch_stage of instruction_fetch_stage.v
	wire [31:0]	if_instruction1;	// From instruction_fetch_stage of instruction_fetch_stage.v
	wire [31:0]	if_instruction2;	// From instruction_fetch_stage of instruction_fetch_stage.v
	wire [31:0]	if_instruction3;	// From instruction_fetch_stage of instruction_fetch_stage.v
	wire		if_instruction_valid0;	// From instruction_fetch_stage of instruction_fetch_stage.v
	wire		if_instruction_valid1;	// From instruction_fetch_stage of instruction_fetch_stage.v
	wire		if_instruction_valid2;	// From instruction_fetch_stage of instruction_fetch_stage.v
	wire		if_instruction_valid3;	// From instruction_fetch_stage of instruction_fetch_stage.v
	wire		if_long_latency0;	// From instruction_fetch_stage of instruction_fetch_stage.v
	wire		if_long_latency1;	// From instruction_fetch_stage of instruction_fetch_stage.v
	wire		if_long_latency2;	// From instruction_fetch_stage of instruction_fetch_stage.v
	wire		if_long_latency3;	// From instruction_fetch_stage of instruction_fetch_stage.v
	wire [31:0]	if_pc0;			// From instruction_fetch_stage of instruction_fetch_stage.v
	wire [31:0]	if_pc1;			// From instruction_fetch_stage of instruction_fetch_stage.v
	wire [31:0]	if_pc2;			// From instruction_fetch_stage of instruction_fetch_stage.v
	wire [31:0]	if_pc3;			// From instruction_fetch_stage of instruction_fetch_stage.v
	wire		ma_alignment_fault;	// From memory_access_stage of memory_access_stage.v
	wire [3:0]	ma_cache_lane_select;	// From memory_access_stage of memory_access_stage.v
	wire [4:0]	ma_cr_index;		// From memory_access_stage of memory_access_stage.v
	wire		ma_cr_read_en;		// From memory_access_stage of memory_access_stage.v
	wire		ma_cr_write_en;		// From memory_access_stage of memory_access_stage.v
	wire [31:0]	ma_cr_write_value;	// From memory_access_stage of memory_access_stage.v
	wire		ma_enable_scalar_writeback;// From memory_access_stage of memory_access_stage.v
	wire		ma_enable_vector_writeback;// From memory_access_stage of memory_access_stage.v
	wire [31:0]	ma_instruction;		// From memory_access_stage of memory_access_stage.v
	wire [31:0]	ma_io_response;		// From memory_access_stage of memory_access_stage.v
	wire [15:0]	ma_mask;		// From memory_access_stage of memory_access_stage.v
	wire [31:0]	ma_pc;			// From memory_access_stage of memory_access_stage.v
	wire [3:0]	ma_reg_lane_select;	// From memory_access_stage of memory_access_stage.v
	wire [511:0]	ma_result;		// From memory_access_stage of memory_access_stage.v
	wire [1:0]	ma_strand;		// From memory_access_stage of memory_access_stage.v
	wire [31:0]	ma_strided_offset;	// From memory_access_stage of memory_access_stage.v
	wire		ma_was_io;		// From memory_access_stage of memory_access_stage.v
	wire		ma_was_load;		// From memory_access_stage of memory_access_stage.v
	wire [6:0]	ma_writeback_reg;	// From memory_access_stage of memory_access_stage.v
	wire		rb_retry_strand0;	// From rollback_controller of rollback_controller.v
	wire		rb_retry_strand1;	// From rollback_controller of rollback_controller.v
	wire		rb_retry_strand2;	// From rollback_controller of rollback_controller.v
	wire		rb_retry_strand3;	// From rollback_controller of rollback_controller.v
	wire [31:0]	rb_rollback_pc0;	// From rollback_controller of rollback_controller.v
	wire [31:0]	rb_rollback_pc1;	// From rollback_controller of rollback_controller.v
	wire [31:0]	rb_rollback_pc2;	// From rollback_controller of rollback_controller.v
	wire [31:0]	rb_rollback_pc3;	// From rollback_controller of rollback_controller.v
	wire		rb_rollback_strand0;	// From rollback_controller of rollback_controller.v
	wire		rb_rollback_strand1;	// From rollback_controller of rollback_controller.v
	wire		rb_rollback_strand2;	// From rollback_controller of rollback_controller.v
	wire		rb_rollback_strand3;	// From rollback_controller of rollback_controller.v
	wire [3:0]	rollback_reg_lane0;	// From rollback_controller of rollback_controller.v
	wire [3:0]	rollback_reg_lane1;	// From rollback_controller of rollback_controller.v
	wire [3:0]	rollback_reg_lane2;	// From rollback_controller of rollback_controller.v
	wire [3:0]	rollback_reg_lane3;	// From rollback_controller of rollback_controller.v
	wire [31:0]	rollback_strided_offset0;// From rollback_controller of rollback_controller.v
	wire [31:0]	rollback_strided_offset1;// From rollback_controller of rollback_controller.v
	wire [31:0]	rollback_strided_offset2;// From rollback_controller of rollback_controller.v
	wire [31:0]	rollback_strided_offset3;// From rollback_controller of rollback_controller.v
	wire [31:0]	scalar_value1;		// From scalar_register_file of scalar_register_file.v
	wire [31:0]	scalar_value2;		// From scalar_register_file of scalar_register_file.v
	wire		squash_ds;		// From rollback_controller of rollback_controller.v
	wire		squash_ex0;		// From rollback_controller of rollback_controller.v
	wire		squash_ex1;		// From rollback_controller of rollback_controller.v
	wire		squash_ex2;		// From rollback_controller of rollback_controller.v
	wire		squash_ex3;		// From rollback_controller of rollback_controller.v
	wire		squash_ma;		// From rollback_controller of rollback_controller.v
	wire		ss_branch_predicted;	// From strand_select_stage of strand_select_stage.v
	wire [31:0]	ss_instruction;		// From strand_select_stage of strand_select_stage.v
	wire		ss_instruction_req0;	// From strand_select_stage of strand_select_stage.v
	wire		ss_instruction_req1;	// From strand_select_stage of strand_select_stage.v
	wire		ss_instruction_req2;	// From strand_select_stage of strand_select_stage.v
	wire		ss_instruction_req3;	// From strand_select_stage of strand_select_stage.v
	wire		ss_long_latency;	// From strand_select_stage of strand_select_stage.v
	wire [31:0]	ss_pc;			// From strand_select_stage of strand_select_stage.v
	wire [3:0]	ss_reg_lane_select;	// From strand_select_stage of strand_select_stage.v
	wire [1:0]	ss_strand;		// From strand_select_stage of strand_select_stage.v
	wire [31:0]	ss_strided_offset;	// From strand_select_stage of strand_select_stage.v
	wire		suspend_strand0;	// From rollback_controller of rollback_controller.v
	wire		suspend_strand1;	// From rollback_controller of rollback_controller.v
	wire		suspend_strand2;	// From rollback_controller of rollback_controller.v
	wire		suspend_strand3;	// From rollback_controller of rollback_controller.v
	wire [511:0]	vector_value1;		// From vector_register_file of vector_register_file.v
	wire [511:0]	vector_value2;		// From vector_register_file of vector_register_file.v
	wire		wb_enable_scalar_writeback;// From writeback_stage of writeback_stage.v
	wire		wb_enable_vector_writeback;// From writeback_stage of writeback_stage.v
	wire [31:0]	wb_fault_pc;		// From writeback_stage of writeback_stage.v
	wire [1:0]	wb_fault_strand;	// From writeback_stage of writeback_stage.v
	wire		wb_latch_fault;		// From writeback_stage of writeback_stage.v
	wire		wb_retry;		// From writeback_stage of writeback_stage.v
	wire [31:0]	wb_rollback_pc;		// From writeback_stage of writeback_stage.v
	wire		wb_rollback_request;	// From writeback_stage of writeback_stage.v
	wire		wb_suspend_request;	// From writeback_stage of writeback_stage.v
	wire [15:0]	wb_writeback_mask;	// From writeback_stage of writeback_stage.v
	wire [6:0]	wb_writeback_reg;	// From writeback_stage of writeback_stage.v
	wire [511:0]	wb_writeback_value;	// From writeback_stage of writeback_stage.v
	// End of automatics

	assign halt_o = cr_strand_enable == 0;	// If all threads disabled, halt

	instruction_fetch_stage instruction_fetch_stage(/*AUTOINST*/
							// Outputs
							.icache_addr	(icache_addr[31:0]),
							.icache_request	(icache_request),
							.icache_req_strand(icache_req_strand[1:0]),
							.if_instruction0(if_instruction0[31:0]),
							.if_instruction_valid0(if_instruction_valid0),
							.if_pc0		(if_pc0[31:0]),
							.if_branch_predicted0(if_branch_predicted0),
							.if_long_latency0(if_long_latency0),
							.if_instruction1(if_instruction1[31:0]),
							.if_instruction_valid1(if_instruction_valid1),
							.if_pc1		(if_pc1[31:0]),
							.if_branch_predicted1(if_branch_predicted1),
							.if_long_latency1(if_long_latency1),
							.if_instruction2(if_instruction2[31:0]),
							.if_instruction_valid2(if_instruction_valid2),
							.if_pc2		(if_pc2[31:0]),
							.if_branch_predicted2(if_branch_predicted2),
							.if_long_latency2(if_long_latency2),
							.if_instruction3(if_instruction3[31:0]),
							.if_instruction_valid3(if_instruction_valid3),
							.if_pc3		(if_pc3[31:0]),
							.if_branch_predicted3(if_branch_predicted3),
							.if_long_latency3(if_long_latency3),
							// Inputs
							.clk		(clk),
							.reset		(reset),
							.icache_data	(icache_data[31:0]),
							.icache_hit	(icache_hit),
							.icache_load_complete_strands(icache_load_complete_strands[3:0]),
							.icache_load_collision(icache_load_collision),
							.ss_instruction_req0(ss_instruction_req0),
							.rb_rollback_strand0(rb_rollback_strand0),
							.rb_rollback_pc0(rb_rollback_pc0[31:0]),
							.ss_instruction_req1(ss_instruction_req1),
							.rb_rollback_strand1(rb_rollback_strand1),
							.rb_rollback_pc1(rb_rollback_pc1[31:0]),
							.ss_instruction_req2(ss_instruction_req2),
							.rb_rollback_strand2(rb_rollback_strand2),
							.rb_rollback_pc2(rb_rollback_pc2[31:0]),
							.ss_instruction_req3(ss_instruction_req3),
							.rb_rollback_strand3(rb_rollback_strand3),
							.rb_rollback_pc3(rb_rollback_pc3[31:0]));

	wire resume_strand0 = dcache_resume_strands[0];
	wire resume_strand1 = dcache_resume_strands[1];
	wire resume_strand2 = dcache_resume_strands[2];
	wire resume_strand3 = dcache_resume_strands[3];

	strand_select_stage strand_select_stage(/*AUTOINST*/
						// Outputs
						.ss_instruction_req0(ss_instruction_req0),
						.ss_instruction_req1(ss_instruction_req1),
						.ss_instruction_req2(ss_instruction_req2),
						.ss_instruction_req3(ss_instruction_req3),
						.ss_pc		(ss_pc[31:0]),
						.ss_instruction	(ss_instruction[31:0]),
						.ss_reg_lane_select(ss_reg_lane_select[3:0]),
						.ss_strided_offset(ss_strided_offset[31:0]),
						.ss_strand	(ss_strand[1:0]),
						.ss_branch_predicted(ss_branch_predicted),
						.ss_long_latency(ss_long_latency),
						.pc_event_raw_wait(pc_event_raw_wait[3:0]),
						.pc_event_dcache_wait(pc_event_dcache_wait[3:0]),
						.pc_event_icache_wait(pc_event_icache_wait[3:0]),
						.pc_event_instruction_issue(pc_event_instruction_issue),
						// Inputs
						.clk		(clk),
						.reset		(reset),
						.cr_strand_enable(cr_strand_enable[3:0]),
						.if_instruction0(if_instruction0[31:0]),
						.if_instruction_valid0(if_instruction_valid0),
						.if_pc0		(if_pc0[31:0]),
						.if_branch_predicted0(if_branch_predicted0),
						.if_long_latency0(if_long_latency0),
						.rb_rollback_strand0(rb_rollback_strand0),
						.rb_retry_strand0(rb_retry_strand0),
						.suspend_strand0(suspend_strand0),
						.resume_strand0	(resume_strand0),
						.rollback_strided_offset0(rollback_strided_offset0[31:0]),
						.rollback_reg_lane0(rollback_reg_lane0[3:0]),
						.if_instruction1(if_instruction1[31:0]),
						.if_instruction_valid1(if_instruction_valid1),
						.if_pc1		(if_pc1[31:0]),
						.if_branch_predicted1(if_branch_predicted1),
						.if_long_latency1(if_long_latency1),
						.rb_rollback_strand1(rb_rollback_strand1),
						.rb_retry_strand1(rb_retry_strand1),
						.suspend_strand1(suspend_strand1),
						.resume_strand1	(resume_strand1),
						.rollback_strided_offset1(rollback_strided_offset1[31:0]),
						.rollback_reg_lane1(rollback_reg_lane1[3:0]),
						.if_instruction2(if_instruction2[31:0]),
						.if_instruction_valid2(if_instruction_valid2),
						.if_pc2		(if_pc2[31:0]),
						.if_branch_predicted2(if_branch_predicted2),
						.if_long_latency2(if_long_latency2),
						.rb_rollback_strand2(rb_rollback_strand2),
						.rb_retry_strand2(rb_retry_strand2),
						.suspend_strand2(suspend_strand2),
						.resume_strand2	(resume_strand2),
						.rollback_strided_offset2(rollback_strided_offset2[31:0]),
						.rollback_reg_lane2(rollback_reg_lane2[3:0]),
						.if_instruction3(if_instruction3[31:0]),
						.if_instruction_valid3(if_instruction_valid3),
						.if_pc3		(if_pc3[31:0]),
						.if_branch_predicted3(if_branch_predicted3),
						.if_long_latency3(if_long_latency3),
						.rb_rollback_strand3(rb_rollback_strand3),
						.rb_retry_strand3(rb_retry_strand3),
						.suspend_strand3(suspend_strand3),
						.resume_strand3	(resume_strand3),
						.rollback_strided_offset3(rollback_strided_offset3[31:0]),
						.rollback_reg_lane3(rollback_reg_lane3[3:0]));

	decode_stage decode_stage(/*AUTOINST*/
				  // Outputs
				  .ds_scalar_sel1	(ds_scalar_sel1[6:0]),
				  .ds_scalar_sel2	(ds_scalar_sel2[6:0]),
				  .ds_vector_sel1	(ds_vector_sel1[6:0]),
				  .ds_vector_sel2	(ds_vector_sel2[6:0]),
				  .ds_instruction	(ds_instruction[31:0]),
				  .ds_strand		(ds_strand[1:0]),
				  .ds_pc		(ds_pc[31:0]),
				  .ds_immediate_value	(ds_immediate_value[31:0]),
				  .ds_mask_src		(ds_mask_src[2:0]),
				  .ds_op1_is_vector	(ds_op1_is_vector),
				  .ds_op2_src		(ds_op2_src[1:0]),
				  .ds_store_value_is_vector(ds_store_value_is_vector),
				  .ds_writeback_reg	(ds_writeback_reg[6:0]),
				  .ds_enable_scalar_writeback(ds_enable_scalar_writeback),
				  .ds_enable_vector_writeback(ds_enable_vector_writeback),
				  .ds_alu_op		(ds_alu_op[5:0]),
				  .ds_reg_lane_select	(ds_reg_lane_select[3:0]),
				  .ds_strided_offset	(ds_strided_offset[31:0]),
				  .ds_branch_predicted	(ds_branch_predicted),
				  .ds_long_latency	(ds_long_latency),
				  .ds_vector_sel1_l	(ds_vector_sel1_l[6:0]),
				  .ds_vector_sel2_l	(ds_vector_sel2_l[6:0]),
				  .ds_scalar_sel1_l	(ds_scalar_sel1_l[6:0]),
				  .ds_scalar_sel2_l	(ds_scalar_sel2_l[6:0]),
				  // Inputs
				  .clk			(clk),
				  .reset		(reset),
				  .squash_ds		(squash_ds),
				  .ss_instruction	(ss_instruction[31:0]),
				  .ss_strand		(ss_strand[1:0]),
				  .ss_branch_predicted	(ss_branch_predicted),
				  .ss_pc		(ss_pc[31:0]),
				  .ss_strided_offset	(ss_strided_offset[31:0]),
				  .ss_long_latency	(ss_long_latency),
				  .ss_reg_lane_select	(ss_reg_lane_select[3:0]));

	assert_false #("simultaneous vector and scalar writeback") a0(.clk(clk),
		.test(wb_enable_scalar_writeback && wb_enable_vector_writeback));

	scalar_register_file scalar_register_file(/*AUTOINST*/
						  // Outputs
						  .scalar_value1	(scalar_value1[31:0]),
						  .scalar_value2	(scalar_value2[31:0]),
						  // Inputs
						  .clk			(clk),
						  .reset		(reset),
						  .ds_scalar_sel1	(ds_scalar_sel1[6:0]),
						  .ds_scalar_sel2	(ds_scalar_sel2[6:0]),
						  .wb_writeback_reg	(wb_writeback_reg[6:0]),
						  .wb_writeback_value	(wb_writeback_value[31:0]),
						  .wb_enable_scalar_writeback(wb_enable_scalar_writeback));
	
	vector_register_file vector_register_file(/*AUTOINST*/
						  // Outputs
						  .vector_value1	(vector_value1[511:0]),
						  .vector_value2	(vector_value2[511:0]),
						  // Inputs
						  .clk			(clk),
						  .reset		(reset),
						  .ds_vector_sel1	(ds_vector_sel1[6:0]),
						  .ds_vector_sel2	(ds_vector_sel2[6:0]),
						  .wb_writeback_reg	(wb_writeback_reg[6:0]),
						  .wb_writeback_value	(wb_writeback_value[511:0]),
						  .wb_writeback_mask	(wb_writeback_mask[15:0]),
						  .wb_enable_vector_writeback(wb_enable_vector_writeback));
	
	execute_stage execute_stage(/*AUTOINST*/
				    // Outputs
				    .ex_instruction	(ex_instruction[31:0]),
				    .ex_strand		(ex_strand[1:0]),
				    .ex_pc		(ex_pc[31:0]),
				    .ex_store_value	(ex_store_value[511:0]),
				    .ex_writeback_reg	(ex_writeback_reg[6:0]),
				    .ex_enable_scalar_writeback(ex_enable_scalar_writeback),
				    .ex_enable_vector_writeback(ex_enable_vector_writeback),
				    .ex_mask		(ex_mask[15:0]),
				    .ex_result		(ex_result[511:0]),
				    .ex_reg_lane_select	(ex_reg_lane_select[3:0]),
				    .ex_strided_offset	(ex_strided_offset[31:0]),
				    .ex_base_addr	(ex_base_addr[31:0]),
				    .ex_rollback_request(ex_rollback_request),
				    .ex_rollback_pc	(ex_rollback_pc[31:0]),
				    .ex_strand1		(ex_strand1[1:0]),
				    .ex_strand2		(ex_strand2[1:0]),
				    .ex_strand3		(ex_strand3[1:0]),
				    .pc_event_mispredicted_branch(pc_event_mispredicted_branch),
				    .pc_event_uncond_branch(pc_event_uncond_branch),
				    .pc_event_cond_branch_taken(pc_event_cond_branch_taken),
				    .pc_event_cond_branch_not_taken(pc_event_cond_branch_not_taken),
				    // Inputs
				    .clk		(clk),
				    .reset		(reset),
				    .ds_instruction	(ds_instruction[31:0]),
				    .ds_branch_predicted(ds_branch_predicted),
				    .ds_strand		(ds_strand[1:0]),
				    .ds_pc		(ds_pc[31:0]),
				    .ds_immediate_value	(ds_immediate_value[31:0]),
				    .ds_mask_src	(ds_mask_src[2:0]),
				    .ds_op1_is_vector	(ds_op1_is_vector),
				    .ds_op2_src		(ds_op2_src[1:0]),
				    .ds_store_value_is_vector(ds_store_value_is_vector),
				    .ds_writeback_reg	(ds_writeback_reg[6:0]),
				    .ds_enable_scalar_writeback(ds_enable_scalar_writeback),
				    .ds_enable_vector_writeback(ds_enable_vector_writeback),
				    .ds_alu_op		(ds_alu_op[5:0]),
				    .ds_reg_lane_select	(ds_reg_lane_select[3:0]),
				    .ds_strided_offset	(ds_strided_offset[31:0]),
				    .ds_long_latency	(ds_long_latency),
				    .ds_scalar_sel1_l	(ds_scalar_sel1_l[6:0]),
				    .ds_scalar_sel2_l	(ds_scalar_sel2_l[6:0]),
				    .ds_vector_sel1_l	(ds_vector_sel1_l[6:0]),
				    .ds_vector_sel2_l	(ds_vector_sel2_l[6:0]),
				    .scalar_value1	(scalar_value1[31:0]),
				    .scalar_value2	(scalar_value2[31:0]),
				    .vector_value1	(vector_value1[511:0]),
				    .vector_value2	(vector_value2[511:0]),
				    .squash_ex0		(squash_ex0),
				    .squash_ex1		(squash_ex1),
				    .squash_ex2		(squash_ex2),
				    .squash_ex3		(squash_ex3),
				    .ma_writeback_reg	(ma_writeback_reg[6:0]),
				    .ma_enable_scalar_writeback(ma_enable_scalar_writeback),
				    .ma_enable_vector_writeback(ma_enable_vector_writeback),
				    .ma_result		(ma_result[511:0]),
				    .ma_mask		(ma_mask[15:0]),
				    .wb_writeback_reg	(wb_writeback_reg[6:0]),
				    .wb_enable_scalar_writeback(wb_enable_scalar_writeback),
				    .wb_enable_vector_writeback(wb_enable_vector_writeback),
				    .wb_writeback_value	(wb_writeback_value[511:0]),
				    .wb_writeback_mask	(wb_writeback_mask[15:0]),
				    .rf_writeback_reg	(rf_writeback_reg[6:0]),
				    .rf_enable_scalar_writeback(rf_enable_scalar_writeback),
				    .rf_enable_vector_writeback(rf_enable_vector_writeback),
				    .rf_writeback_value	(rf_writeback_value[511:0]),
				    .rf_writeback_mask	(rf_writeback_mask[15:0]));

	assign dcache_req_strand = ex_strand;
		
	memory_access_stage memory_access_stage(
		/*AUTOINST*/
						// Outputs
						.ma_strand	(ma_strand[1:0]),
						.ma_instruction	(ma_instruction[31:0]),
						.ma_pc		(ma_pc[31:0]),
						.ma_writeback_reg(ma_writeback_reg[6:0]),
						.ma_enable_scalar_writeback(ma_enable_scalar_writeback),
						.ma_enable_vector_writeback(ma_enable_vector_writeback),
						.ma_mask	(ma_mask[15:0]),
						.ma_result	(ma_result[511:0]),
						.ma_reg_lane_select(ma_reg_lane_select[3:0]),
						.ma_cache_lane_select(ma_cache_lane_select[3:0]),
						.ma_was_load	(ma_was_load),
						.ma_strided_offset(ma_strided_offset[31:0]),
						.ma_alignment_fault(ma_alignment_fault),
						.ma_was_io	(ma_was_io),
						.ma_io_response	(ma_io_response[31:0]),
						.ma_cr_index	(ma_cr_index[4:0]),
						.ma_cr_read_en	(ma_cr_read_en),
						.ma_cr_write_en	(ma_cr_write_en),
						.ma_cr_write_value(ma_cr_write_value[31:0]),
						.io_write_en	(io_write_en),
						.io_read_en	(io_read_en),
						.io_address	(io_address[31:0]),
						.io_write_data	(io_write_data[31:0]),
						.dcache_addr	(dcache_addr[25:0]),
						.dcache_req_sync(dcache_req_sync),
						.dcache_req_strand(dcache_req_strand[1:0]),
						.data_to_dcache	(data_to_dcache[511:0]),
						.dcache_load	(dcache_load),
						.dcache_store	(dcache_store),
						.dcache_flush	(dcache_flush),
						.dcache_stbar	(dcache_stbar),
						.dcache_dinvalidate(dcache_dinvalidate),
						.dcache_iinvalidate(dcache_iinvalidate),
						.dcache_store_mask(dcache_store_mask[63:0]),
						// Inputs
						.clk		(clk),
						.reset		(reset),
						.squash_ma	(squash_ma),
						.ex_instruction	(ex_instruction[31:0]),
						.ex_strand	(ex_strand[1:0]),
						.ex_store_value	(ex_store_value[511:0]),
						.ex_writeback_reg(ex_writeback_reg[6:0]),
						.ex_enable_scalar_writeback(ex_enable_scalar_writeback),
						.ex_enable_vector_writeback(ex_enable_vector_writeback),
						.ex_pc		(ex_pc[31:0]),
						.ex_mask	(ex_mask[15:0]),
						.ex_result	(ex_result[511:0]),
						.ex_reg_lane_select(ex_reg_lane_select[3:0]),
						.ex_strided_offset(ex_strided_offset[31:0]),
						.ex_base_addr	(ex_base_addr[31:0]),
						.cr_read_value	(cr_read_value[31:0]),
						.io_read_data	(io_read_data[31:0]));

	writeback_stage writeback_stage(/*AUTOINST*/
					// Outputs
					.wb_enable_scalar_writeback(wb_enable_scalar_writeback),
					.wb_enable_vector_writeback(wb_enable_vector_writeback),
					.wb_writeback_reg(wb_writeback_reg[6:0]),
					.wb_writeback_value(wb_writeback_value[511:0]),
					.wb_writeback_mask(wb_writeback_mask[15:0]),
					.wb_latch_fault	(wb_latch_fault),
					.wb_fault_pc	(wb_fault_pc[31:0]),
					.wb_fault_strand(wb_fault_strand[1:0]),
					.wb_rollback_request(wb_rollback_request),
					.wb_rollback_pc	(wb_rollback_pc[31:0]),
					.wb_suspend_request(wb_suspend_request),
					.wb_retry	(wb_retry),
					.pc_event_instruction_retire(pc_event_instruction_retire),
					// Inputs
					.clk		(clk),
					.reset		(reset),
					.dcache_hit	(dcache_hit),
					.data_from_dcache(data_from_dcache[511:0]),
					.dcache_load_collision(dcache_load_collision),
					.stbuf_rollback	(stbuf_rollback),
					.ma_instruction	(ma_instruction[31:0]),
					.ma_pc		(ma_pc[31:0]),
					.ma_writeback_reg(ma_writeback_reg[6:0]),
					.ma_enable_scalar_writeback(ma_enable_scalar_writeback),
					.ma_enable_vector_writeback(ma_enable_vector_writeback),
					.ma_mask	(ma_mask[15:0]),
					.ma_was_load	(ma_was_load),
					.ma_alignment_fault(ma_alignment_fault),
					.ma_result	(ma_result[511:0]),
					.ma_reg_lane_select(ma_reg_lane_select[3:0]),
					.ma_cache_lane_select(ma_cache_lane_select[3:0]),
					.ma_strand	(ma_strand[1:0]),
					.ma_was_io	(ma_was_io),
					.ma_io_response	(ma_io_response[31:0]),
					.cr_exception_handler_address(cr_exception_handler_address[31:0]));
	
	control_registers #(.CORE_ID(CORE_ID)) control_registers(
		/*AUTOINST*/
								 // Outputs
								 .cr_strand_enable	(cr_strand_enable[3:0]),
								 .cr_exception_handler_address(cr_exception_handler_address[31:0]),
								 .cr_read_value		(cr_read_value[31:0]),
								 // Inputs
								 .clk			(clk),
								 .reset			(reset),
								 .wb_latch_fault	(wb_latch_fault),
								 .wb_fault_pc		(wb_fault_pc[31:0]),
								 .wb_fault_strand	(wb_fault_strand[1:0]),
								 .ex_strand		(ex_strand[1:0]),
								 .ma_cr_index		(ma_cr_index[4:0]),
								 .ma_cr_read_en		(ma_cr_read_en),
								 .ma_cr_write_en	(ma_cr_write_en),
								 .ma_cr_write_value	(ma_cr_write_value[31:0]));
	
	// Even though the results have already been committed to the
	// register file on this cycle, the new register values were
	// fetched a cycle before the bypass stage, so we may still
	// have stale results there.
	always @(posedge clk, posedge reset)
	begin
		if (reset)
		begin
			/*AUTORESET*/
			// Beginning of autoreset for uninitialized flops
			rf_enable_scalar_writeback <= 1'h0;
			rf_enable_vector_writeback <= 1'h0;
			rf_writeback_mask <= 16'h0;
			rf_writeback_reg <= 7'h0;
			rf_writeback_value <= 512'h0;
			// End of automatics
		end
		else
		begin
			rf_writeback_reg			<= wb_writeback_reg;
			rf_writeback_value			<= wb_writeback_value;
			rf_writeback_mask			<= wb_writeback_mask;
			rf_enable_vector_writeback	<= wb_enable_vector_writeback;
			rf_enable_scalar_writeback	<= wb_enable_scalar_writeback;
		end
	end

	rollback_controller rollback_controller(
		/*AUTOINST*/
						// Outputs
						.squash_ds	(squash_ds),
						.squash_ex0	(squash_ex0),
						.squash_ex1	(squash_ex1),
						.squash_ex2	(squash_ex2),
						.squash_ex3	(squash_ex3),
						.squash_ma	(squash_ma),
						.rb_rollback_strand0(rb_rollback_strand0),
						.rb_rollback_pc0(rb_rollback_pc0[31:0]),
						.rollback_strided_offset0(rollback_strided_offset0[31:0]),
						.rollback_reg_lane0(rollback_reg_lane0[3:0]),
						.suspend_strand0(suspend_strand0),
						.rb_retry_strand0(rb_retry_strand0),
						.rb_rollback_strand1(rb_rollback_strand1),
						.rb_rollback_pc1(rb_rollback_pc1[31:0]),
						.rollback_strided_offset1(rollback_strided_offset1[31:0]),
						.rollback_reg_lane1(rollback_reg_lane1[3:0]),
						.suspend_strand1(suspend_strand1),
						.rb_retry_strand1(rb_retry_strand1),
						.rb_rollback_strand2(rb_rollback_strand2),
						.rb_rollback_pc2(rb_rollback_pc2[31:0]),
						.rollback_strided_offset2(rollback_strided_offset2[31:0]),
						.rollback_reg_lane2(rollback_reg_lane2[3:0]),
						.suspend_strand2(suspend_strand2),
						.rb_retry_strand2(rb_retry_strand2),
						.rb_rollback_strand3(rb_rollback_strand3),
						.rb_rollback_pc3(rb_rollback_pc3[31:0]),
						.rollback_strided_offset3(rollback_strided_offset3[31:0]),
						.rollback_reg_lane3(rollback_reg_lane3[3:0]),
						.suspend_strand3(suspend_strand3),
						.rb_retry_strand3(rb_retry_strand3),
						// Inputs
						.ss_strand	(ss_strand[1:0]),
						.ex_rollback_request(ex_rollback_request),
						.ex_rollback_pc	(ex_rollback_pc[31:0]),
						.ds_strand	(ds_strand[1:0]),
						.ex_strand	(ex_strand[1:0]),
						.ex_strand1	(ex_strand1[1:0]),
						.ex_strand2	(ex_strand2[1:0]),
						.ex_strand3	(ex_strand3[1:0]),
						.wb_rollback_request(wb_rollback_request),
						.wb_retry	(wb_retry),
						.wb_rollback_pc	(wb_rollback_pc[31:0]),
						.ma_strided_offset(ma_strided_offset[31:0]),
						.ma_reg_lane_select(ma_reg_lane_select[3:0]),
						.ma_strand	(ma_strand[1:0]),
						.wb_suspend_request(wb_suspend_request));
endmodule
