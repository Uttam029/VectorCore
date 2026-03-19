`default_nettype none
`timescale 1ns/1ns

// ============================================================================
// REGISTER FILE
// ============================================================================
// Purpose: Each thread has its own set of 16 registers.
// This is the core of the SIMD model - same instruction, different data
// in each thread's registers.
//
// Register layout (16 registers, 4-bit address):
//   R0  - R11 : General-purpose read/write registers (12 free registers)
//   R12       : %gridDim   (read-only) - Total blocks * threads per block
//   R13       : %blockIdx  (read-only) - Current block index
//   R14       : %blockDim  (read-only) - Number of threads per block
//   R15       : %threadIdx (read-only) - Thread index within the block
//
// The read-only registers are critical to SIMD:
//   - Each thread knows its unique position via %blockIdx, %blockDim, %threadIdx
//   - This allows computing: global_id = blockIdx * blockDim + threadIdx
//   - Each thread uses this to access different elements in memory
//
// Register write sources (via decoded_reg_input_mux):
//   00 = ARITHMETIC : Write ALU result (ADD, SUB, MUL, DIV)
//   01 = MEMORY     : Write LSU result (LDR)
//   10 = CONSTANT   : Write immediate value (CONST)
// ============================================================================
module registers #(
    parameter THREADS_PER_BLOCK = 4,
    parameter THREAD_ID = 0,
    parameter DATA_BITS = 8
) (
    input wire clk,
    input wire reset,
    input wire enable,  // Disabled when block has fewer threads than block size

    // Block metadata from dispatcher
    input reg [7:0] block_id,
    input reg [7:0] total_blocks,

    // Execution state from scheduler
    input reg [2:0] core_state,

    // Instruction signals from decoder
    input reg [3:0] decoded_rd_address,   // Destination register
    input reg [3:0] decoded_rs_address,   // Source register 1
    input reg [3:0] decoded_rt_address,   // Source register 2

    // Control signals from decoder
    input reg decoded_reg_write_enable,           // Enable register write
    input reg [1:0] decoded_reg_input_mux,        // Select write source
    input reg [DATA_BITS-1:0] decoded_immediate,  // Immediate value (CONST)

    // Data inputs from other units
    input reg [DATA_BITS-1:0] alu_out,  // Result from ALU
    input reg [DATA_BITS-1:0] lsu_out,  // Result from LSU (memory load)

    // Register outputs (fed to ALU, LSU, etc.)
    output reg [7:0] rs,  // Source register 1 value
    output reg [7:0] rt   // Source register 2 value
);
    // Write source encoding
    localparam ARITHMETIC = 2'b00,
        MEMORY = 2'b01,
        CONSTANT = 2'b10;

    // 16 registers per thread (8 bits each)
    reg [7:0] registers[15:0];

    always @(posedge clk) begin
        if (reset) begin
            // Clear outputs
            rs <= 0;
            rt <= 0;
            // Initialize all general-purpose registers to 0
            registers[0]  <= 8'b0;
            registers[1]  <= 8'b0;
            registers[2]  <= 8'b0;
            registers[3]  <= 8'b0;
            registers[4]  <= 8'b0;
            registers[5]  <= 8'b0;
            registers[6]  <= 8'b0;
            registers[7]  <= 8'b0;
            registers[8]  <= 8'b0;
            registers[9]  <= 8'b0;
            registers[10] <= 8'b0;
            registers[11] <= 8'b0;
            // Initialize read-only SIMD registers
            registers[12] <= 8'b0;               // %gridDim   (updated each kernel)
            registers[13] <= 8'b0;               // %blockIdx  (updated each block)
            registers[14] <= THREADS_PER_BLOCK;  // %blockDim  (fixed at compile time)
            registers[15] <= THREAD_ID;          // %threadIdx (fixed at compile time)
        end else if (enable) begin
            // Update block_id when dispatcher assigns a new block
            registers[13] <= block_id;
            // Update gridDim (total threads in the grid)
            registers[12] <= total_blocks * THREADS_PER_BLOCK;

            // Read registers during REQUEST stage - feed values to ALU/LSU
            if (core_state == 3'b011) begin
                rs <= registers[decoded_rs_address];
                rt <= registers[decoded_rt_address];
            end

            // Write to destination register during UPDATE stage
            if (core_state == 3'b110) begin
                // Only allow writing to R0-R11 (protect read-only registers)
                if (decoded_reg_write_enable && decoded_rd_address < 12) begin
                    case (decoded_reg_input_mux)
                        ARITHMETIC: begin
                            // ADD, SUB, MUL, DIV result from ALU
                            registers[decoded_rd_address] <= alu_out;
                        end
                        MEMORY: begin
                            // LDR result from LSU (loaded from data memory)
                            registers[decoded_rd_address] <= lsu_out;
                        end
                        CONSTANT: begin
                            // CONST immediate value from instruction
                            registers[decoded_rd_address] <= decoded_immediate;
                        end
                    endcase
                end
            end
        end
    end
endmodule
