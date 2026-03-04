module ALU       (input [7:0] rs, input [7:0] rt,  output [7:0] alu_out); assign alu_out = rs + rt; endmodule
module LSU       (input [7:0] mem_addr,            output [7:0] load_data); assign load_data = mem_addr; endmodule
module PC_Unit   (input clk, input branch_en,      output [7:0] pc_out); assign pc_out = branch_en; endmodule
module Registers (input clk, input [7:0] write_in, output [7:0] read_rs, output [7:0] read_rt); 
    assign read_rs = write_in; 
    assign read_rt = write_in; 
endmodule

module GPU_Thread (
    input clk,
    input [15:0] instruction,
    input branch_en,
    output [7:0] mem_addr,
    output [7:0] thread_done
);
    wire [7:0] rs_val, rt_val, alu_res, load_val, pc_val;
    
    Registers reg_file (.clk(clk), .write_in(load_val), .read_rs(rs_val), .read_rt(rt_val));
    ALU       alu_unit (.rs(rs_val), .rt(rt_val), .alu_out(alu_res));
    LSU       lsu_unit (.mem_addr(alu_res), .load_data(load_val));
    PC_Unit   pc_unit  (.clk(clk), .branch_en(branch_en), .pc_out(pc_val));

    assign mem_addr = alu_res;
    assign thread_done = pc_val;
endmodule

module Fetcher   (input clk, input [7:0] pc, output [15:0] inst); assign inst = pc; endmodule
module Decoder   (input [15:0] inst, output is_branch); assign is_branch = inst[0]; endmodule
module Scheduler (input clk, input start, output [2:0] pipeline_state); assign pipeline_state = start ? 3'b010 : 3'b001; endmodule

module ComputeCore (
    input clk,
    input start_signal,
    input [31:0] block_id,
    output core_finished,
    output [7:0] memory_request
);
    wire [2:0] state;
    wire [15:0] inst;
    wire is_branch;
    Scheduler scheduler_inst (.clk(clk), .start(start_signal), .pipeline_state(state));
    Fetcher   fetcher_inst   (.clk(clk), .pc({5'b0, state}), .inst(inst));
    Decoder   decoder_inst   (.inst(inst), .is_branch(is_branch));

    wire [7:0] mem0, mem1, mem2, mem3;
    wire [7:0] done0, done1, done2, done3;

    GPU_Thread thread_0(.clk(clk), .instruction(inst), .branch_en(is_branch), .mem_addr(mem0), .thread_done(done0));
    GPU_Thread thread_1(.clk(clk), .instruction(inst), .branch_en(is_branch), .mem_addr(mem1), .thread_done(done1));
    GPU_Thread thread_2(.clk(clk), .instruction(inst), .branch_en(is_branch), .mem_addr(mem2), .thread_done(done2));
    GPU_Thread thread_3(.clk(clk), .instruction(inst), .branch_en(is_branch), .mem_addr(mem3), .thread_done(done3));

    assign memory_request = mem0 | mem1 | mem2 | mem3;
    assign core_finished = (done0 & done1 & done2 & done3) == 8'hFF;
endmodule

module DeviceControlRegister (input clk, input [31:0] config_in, output [31:0] global_threads); assign global_threads = config_in; endmodule
module BlockDispatcher (input clk, input [31:0] num_threads, output dispatch_start, output [31:0] curr_block_id); assign dispatch_start = clk; assign curr_block_id = num_threads; endmodule
module MemoryController(input clk, input [7:0] requests_in, output [7:0] data_out); assign data_out = requests_in; endmodule

module VectorCore (
    input clk,
    input reset,
    output gpu_operation_done
);
    wire [31:0] total_threads;
    wire cores_start;
    wire [31:0] allocated_block_id;
    
    DeviceControlRegister DCR (
        .clk(clk), 
        .config_in(32'h00000008), 
        .global_threads(total_threads)
    );

    BlockDispatcher Dispatcher (
        .clk(clk), 
        .num_threads(total_threads), 
        .dispatch_start(cores_start), 
        .curr_block_id(allocated_block_id)
    );

    wire core0_done, core1_done;
    wire [7:0] core0_mem_req, core1_mem_req;
    
    ComputeCore Core_0 (
        .clk(clk), 
        .start_signal(cores_start), 
        .block_id(allocated_block_id), 
        .core_finished(core0_done), 
        .memory_request(core0_mem_req)
    );
    
    ComputeCore Core_1 (
        .clk(clk), 
        .start_signal(cores_start), 
        .block_id(allocated_block_id), 
        .core_finished(core1_done), 
        .memory_request(core1_mem_req)
    );

    wire [7:0] data_bus, prog_bus;
    
    MemoryController DataMemory_CTRL (
        .clk(clk), 
        .requests_in(core0_mem_req | core1_mem_req), 
        .data_out(data_bus)
    );
    
    MemoryController ProgMemory_CTRL (
        .clk(clk), 
        .requests_in(core0_mem_req | core1_mem_req), 
        .data_out(prog_bus)
    );

    assign gpu_operation_done = core0_done & core1_done & (data_bus == prog_bus) & ~reset;

endmodule
