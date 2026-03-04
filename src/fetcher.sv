`default_nettype none
`timescale 1ns/1ns

// ============================================================================
// INSTRUCTION FETCHER
// ============================================================================
// Purpose: Retrieves the instruction at the current PC from program memory.
// Each core has its own fetcher (instructions are shared across all threads
// in a core since they execute the same instruction - SIMD).
//
// Fetch state machine:
//   IDLE     → Waiting for core to enter FETCH stage
//   FETCHING → Request sent to program memory controller, waiting for response
//   FETCHED  → Instruction received and stored, waiting for core to move on
//
// The fetcher communicates through the program memory controller which
// arbitrates access to the external program memory.
// ============================================================================
module fetcher #(
    parameter PROGRAM_MEM_ADDR_BITS = 8,
    parameter PROGRAM_MEM_DATA_BITS = 16
) (
    input wire clk,
    input wire reset,

    // Execution state from scheduler
    input reg [2:0] core_state,
    input reg [7:0] current_pc,

    // Program memory interface (to memory controller)
    output reg mem_read_valid,
    output reg [PROGRAM_MEM_ADDR_BITS-1:0] mem_read_address,
    input reg mem_read_ready,
    input reg [PROGRAM_MEM_DATA_BITS-1:0] mem_read_data,

    // Fetcher outputs
    output reg [2:0] fetcher_state,
    output reg [PROGRAM_MEM_DATA_BITS-1:0] instruction
);
    // Fetcher state machine
    localparam IDLE = 3'b000,
        FETCHING = 3'b001,
        FETCHED = 3'b010;

    always @(posedge clk) begin
        if (reset) begin
            fetcher_state <= IDLE;
            mem_read_valid <= 0;
            mem_read_address <= 0;
            instruction <= {PROGRAM_MEM_DATA_BITS{1'b0}};
        end else begin
            case (fetcher_state)
                IDLE: begin
                    // Start fetching when core enters FETCH stage
                    if (core_state == 3'b001) begin
                        fetcher_state <= FETCHING;
                        mem_read_valid <= 1;
                        mem_read_address <= current_pc;
                    end
                end
                FETCHING: begin
                    // Wait for program memory controller to return the instruction
                    if (mem_read_ready) begin
                        fetcher_state <= FETCHED;
                        instruction <= mem_read_data;
                        mem_read_valid <= 0;
                    end
                end
                FETCHED: begin
                    // Reset when core moves to DECODE stage
                    if (core_state == 3'b010) begin
                        fetcher_state <= IDLE;
                    end
                end
            endcase
        end
    end
endmodule
