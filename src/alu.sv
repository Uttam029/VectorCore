`default_nettype none
`timescale 1ns/1ns

// ============================================================================
// ARITHMETIC-LOGIC UNIT (ALU)
// ============================================================================
// Purpose: Executes computations on register values for a single thread.
// Each thread in each core has its own dedicated ALU.
//
// Supported operations:
//   - ADD (00): rs + rt
//   - SUB (01): rs - rt
//   - MUL (10): rs * rt
//   - DIV (11): rs / rt
//   - CMP:      Compare rs and rt, output {Negative, Zero, Positive} bits
//
// The ALU executes during the EXECUTE stage (core_state == 3'b101).
// ============================================================================
module alu (
    input wire clk,
    input wire reset,
    input wire enable,  // Disabled when block has fewer threads than block size

    // Execution state from scheduler
    input reg [2:0] core_state,

    // Control signals from decoder
    input reg [1:0] decoded_alu_arithmetic_mux,  // Selects ADD/SUB/MUL/DIV
    input reg decoded_alu_output_mux,             // 0=arithmetic, 1=compare(CMP)

    // Register values (operands)
    input reg [7:0] rs,
    input reg [7:0] rt,

    // ALU result
    output wire [7:0] alu_out
);
    // Arithmetic operation encoding
    localparam ADD = 2'b00,
        SUB = 2'b01,
        MUL = 2'b10,
        DIV = 2'b11;

    reg [7:0] alu_out_reg;
    assign alu_out = alu_out_reg;

    always @(posedge clk) begin
        if (reset) begin
            alu_out_reg <= 8'b0;
        end else if (enable) begin
            // Only compute during EXECUTE stage
            if (core_state == 3'b101) begin
                if (decoded_alu_output_mux == 1) begin
                    // CMP instruction: set NZP bits based on (rs - rt)
                    // Bit 2 = Negative (rs < rt)
                    // Bit 1 = Zero     (rs == rt)
                    // Bit 0 = Positive (rs > rt)
                    alu_out_reg <= {5'b0, (rs - rt > 0), (rs - rt == 0), (rs - rt < 0)};
                end else begin
                    // Standard arithmetic operations
                    case (decoded_alu_arithmetic_mux)
                        ADD: alu_out_reg <= rs + rt;
                        SUB: alu_out_reg <= rs - rt;
                        MUL: alu_out_reg <= rs * rt;
                        DIV: alu_out_reg <= rs / rt;
                    endcase
                end
            end
        end
    end
endmodule
