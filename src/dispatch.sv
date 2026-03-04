`default_nettype none
`timescale 1ns/1ns

// ============================================================================
// BLOCK DISPATCHER
// ============================================================================
// Purpose: Manages the distribution of thread blocks to compute cores.
// The GPU has ONE dispatcher at the top level.
//
// How it works:
//   1. On kernel start, calculates total_blocks = ceil(thread_count / THREADS_PER_BLOCK)
//   2. Assigns blocks to available cores (up to NUM_CORES simultaneously)
//   3. When a core finishes its block, resets it and assigns the next pending block
//   4. When ALL blocks are done, signals overall kernel completion
//
// Example with 8 threads, 4 threads/block, 2 cores:
//   - total_blocks = 2
//   - Block 0 → Core 0, Block 1 → Core 1  (both start simultaneously)
//   - Both cores finish → done = 1
//
// Example with 12 threads, 4 threads/block, 2 cores:
//   - total_blocks = 3
//   - Block 0 → Core 0, Block 1 → Core 1  (both start)
//   - Core 0 finishes first → Block 2 → Core 0
//   - Both cores finish → done = 1
// ============================================================================
module dispatch #(
    parameter NUM_CORES = 2,
    parameter THREADS_PER_BLOCK = 4
) (
    input wire clk,
    input wire reset,
    input wire start,

    // Kernel metadata from DCR
    input wire [7:0] thread_count,

    // Core control signals
    input reg [NUM_CORES-1:0] core_done,
    output reg [NUM_CORES-1:0] core_start,
    output reg [NUM_CORES-1:0] core_reset,
    output reg [7:0] core_block_id [NUM_CORES-1:0],
    output reg [$clog2(THREADS_PER_BLOCK):0] core_thread_count [NUM_CORES-1:0],

    // Kernel completion signal
    output reg done
);
    // Calculate total blocks needed (ceiling division)
    wire [7:0] total_blocks;
    assign total_blocks = (thread_count + THREADS_PER_BLOCK - 1) / THREADS_PER_BLOCK;

    // Dispatch tracking
    reg [7:0] blocks_dispatched;  // How many blocks have been sent to cores?
    reg [7:0] blocks_done;        // How many blocks have finished processing?
    reg start_execution;           // Prevents re-initialization on every cycle

    always @(posedge clk) begin
        if (reset) begin
            done <= 0;
            blocks_dispatched = 0;
            blocks_done = 0;
            start_execution <= 0;

            for (int i = 0; i < NUM_CORES; i++) begin
                core_start[i] <= 0;
                core_reset[i] <= 1;       // Start with all cores in reset
                core_block_id[i] <= 0;
                core_thread_count[i] <= THREADS_PER_BLOCK;
            end
        end else if (start) begin
            // One-time initialization when kernel starts
            if (!start_execution) begin
                start_execution <= 1;
                for (int i = 0; i < NUM_CORES; i++) begin
                    core_reset[i] <= 1;
                end
            end

            // Check if all blocks are complete
            if (blocks_done == total_blocks) begin
                done <= 1;
            end

            // Assign blocks to cores that just came out of reset
            for (int i = 0; i < NUM_CORES; i++) begin
                if (core_reset[i]) begin
                    core_reset[i] <= 0;

                    // If there are more blocks to dispatch, assign one to this core
                    if (blocks_dispatched < total_blocks) begin
                        core_start[i] <= 1;
                        core_block_id[i] <= blocks_dispatched;
                        // Last block may have fewer threads
                        core_thread_count[i] <= (blocks_dispatched == total_blocks - 1)
                            ? thread_count - (blocks_dispatched * THREADS_PER_BLOCK)
                            : THREADS_PER_BLOCK;

                        blocks_dispatched = blocks_dispatched + 1;
                    end
                end
            end

            // Check for cores that finished their block and need resetting
            for (int i = 0; i < NUM_CORES; i++) begin
                if (core_start[i] && core_done[i]) begin
                    // Core finished - reset it for potential next block
                    core_reset[i] <= 1;
                    core_start[i] <= 0;
                    blocks_done = blocks_done + 1;
                end
            end
        end
    end
endmodule
