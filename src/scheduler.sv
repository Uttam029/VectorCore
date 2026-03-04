`default_nettype none
`timescale 1ns/1ns

// ============================================================================
// SCHEDULER (Core State Machine)
// ============================================================================
// Purpose: Manages the entire control flow of a single compute core.
// Each core has one scheduler that orchestrates the 6-stage pipeline.
//
// Pipeline stages:
//   IDLE    (000) → Waiting for dispatcher to assign a block
//   FETCH   (001) → Fetcher retrieves instruction from program memory
//   DECODE  (010) → Decoder generates control signals from instruction
//   REQUEST (011) → LSUs send memory requests (if LDR/STR), registers read
//   WAIT    (100) → Wait for all async memory operations to complete
//   EXECUTE (101) → ALU computes, PC calculates next address
//   UPDATE  (110) → Write results to registers, update PC
//   DONE    (111) → Block finished (all instructions executed to RET)
//
// Key design decisions:
//   - Sequential execution: one instruction at a time (no pipelining)
//   - All threads must converge: no branch divergence support
//   - Scheduler waits for ALL LSUs before moving past WAIT stage
// ============================================================================
module scheduler #(
    parameter THREADS_PER_BLOCK = 4
) (
    input wire clk,
    input wire reset,
    input wire start,  // Signal from dispatcher to begin processing a block

    // Control signals from decoder
    input reg decoded_mem_read_enable,
    input reg decoded_mem_write_enable,
    input reg decoded_ret,

    // Memory access state
    input reg [2:0] fetcher_state,                          // Is the fetcher done?
    input reg [1:0] lsu_state [THREADS_PER_BLOCK-1:0],     // Are all LSUs done?

    // Program counter management
    output reg [7:0] current_pc,
    input reg [7:0] next_pc [THREADS_PER_BLOCK-1:0],

    // Execution state output (broadcast to all units in the core)
    output reg [2:0] core_state,
    output reg done
);
    // State encoding
    localparam IDLE    = 3'b000,
        FETCH   = 3'b001,
        DECODE  = 3'b010,
        REQUEST = 3'b011,
        WAIT    = 3'b100,
        EXECUTE = 3'b101,
        UPDATE  = 3'b110,
        DONE    = 3'b111;

    always @(posedge clk) begin
        if (reset) begin
            current_pc <= 0;
            core_state <= IDLE;
            done <= 0;
        end else begin
            case (core_state)
                IDLE: begin
                    // Wait for dispatcher to assign and start a block
                    if (start) begin
                        core_state <= FETCH;
                    end
                end
                FETCH: begin
                    // Wait for fetcher to retrieve the instruction
                    // fetcher_state == FETCHED (3'b010) means instruction is ready
                    if (fetcher_state == 3'b010) begin
                        core_state <= DECODE;
                    end
                end
                DECODE: begin
                    // Decode is synchronous (combinational logic), takes 1 cycle
                    core_state <= REQUEST;
                end
                REQUEST: begin
                    // Request is synchronous, takes 1 cycle
                    // LSUs and registers read their values in this stage
                    core_state <= WAIT;
                end
                WAIT: begin
                    // Wait for ALL LSUs to finish their memory operations
                    // This is the most variable-latency stage
                    reg any_lsu_waiting;
                    any_lsu_waiting = 1'b0;
                    for (int i = 0; i < THREADS_PER_BLOCK; i++) begin
                        // Check if any LSU is in REQUESTING (01) or WAITING (10) state
                        if (lsu_state[i] == 2'b01 || lsu_state[i] == 2'b10) begin
                            any_lsu_waiting = 1'b1;
                        end
                    end

                    // Only proceed when all memory operations are complete
                    if (!any_lsu_waiting) begin
                        core_state <= EXECUTE;
                    end
                end
                EXECUTE: begin
                    // Execute is synchronous (ALU computes, PC calculates), takes 1 cycle
                    core_state <= UPDATE;
                end
                UPDATE: begin
                    if (decoded_ret) begin
                        // RET instruction reached - this block is done
                        done <= 1;
                        core_state <= DONE;
                    end else begin
                        // Move to next instruction
                        // NOTE: Assumes all threads converge to same PC (no divergence)
                        current_pc <= next_pc[THREADS_PER_BLOCK-1];
                        core_state <= FETCH;
                    end
                end
                DONE: begin
                    // Stay here until dispatcher resets this core for next block
                end
            endcase
        end
    end
endmodule
