`default_nettype none
`timescale 1ns/1ns

// ============================================================================
// PROGRAM COUNTER (PC)
// ============================================================================
// Purpose: Calculates the next instruction address for each thread.
// Each thread in each core has its own dedicated PC unit.
//
// How it works:
//   - Default: next_pc = current_pc + 1 (sequential execution)
//   - BRnzp:   If the NZP register matches the branch condition,
//              next_pc = immediate (branch target address)
//
// The NZP register:
//   - Set by the CMP instruction via ALU output bits [2:0]
//   - Bit 2 = Negative, Bit 1 = Zero, Bit 0 = Positive
//   - BRnzp checks if (nzp & decoded_nzp) != 0 to decide branching
//
// Note: This simplified GPU assumes all threads converge to the same PC
//       (no branch divergence support).
// ============================================================================
module pc #(
    parameter DATA_MEM_DATA_BITS = 8,
    parameter PROGRAM_MEM_ADDR_BITS = 8
) (
    input wire clk,
    input wire reset,
    input wire enable,  // Disabled when block has fewer threads than block size

    // Execution state from scheduler
    input reg [2:0] core_state,

    // Control signals from decoder
    input reg [2:0] decoded_nzp,                           // Branch condition bits
    input reg [DATA_MEM_DATA_BITS-1:0] decoded_immediate,  // Branch target address
    input reg decoded_nzp_write_enable,                     // Enable NZP register update (CMP)
    input reg decoded_pc_mux,                               // 0=increment, 1=branch

    // ALU output - used for NZP comparison result
    input reg [DATA_MEM_DATA_BITS-1:0] alu_out,

    // Current PC (shared across all threads in a core)
    input reg [PROGRAM_MEM_ADDR_BITS-1:0] current_pc,
    // Next PC (each thread computes its own, but we assume convergence)
    output reg [PROGRAM_MEM_ADDR_BITS-1:0] next_pc
);
    // NZP register: stores result of last CMP instruction
    reg [2:0] nzp;

    always @(posedge clk) begin
        if (reset) begin
            nzp <= 3'b0;
            next_pc <= 0;
        end else if (enable) begin
            // Calculate next PC during EXECUTE stage
            if (core_state == 3'b101) begin
                if (decoded_pc_mux == 1) begin
                    // BRnzp instruction: check if condition matches
                    if (((nzp & decoded_nzp) != 3'b0)) begin
                        // Branch taken - jump to immediate address
                        next_pc <= decoded_immediate;
                    end else begin
                        // Branch not taken - continue to next instruction
                        next_pc <= current_pc + 1;
                    end
                end else begin
                    // Default: advance to next instruction
                    next_pc <= current_pc + 1;
                end
            end

            // Update NZP register during UPDATE stage
            if (core_state == 3'b110) begin
                if (decoded_nzp_write_enable) begin
                    // Store the comparison result from ALU
                    nzp[2] <= alu_out[2];  // Negative
                    nzp[1] <= alu_out[1];  // Zero
                    nzp[0] <= alu_out[0];  // Positive
                end
            end
        end
    end

endmodule
