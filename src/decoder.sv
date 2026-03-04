`default_nettype none
`timescale 1ns/1ns

// ============================================================================
// INSTRUCTION DECODER
// ============================================================================
// Purpose: Decodes a 16-bit instruction into control signals for execution.
// Each core has one decoder (all threads execute the same instruction).
//
// Instruction format (16 bits):
//   [15:12] = OPCODE   (4 bits - selects instruction type)
//   [11:8]  = RD/NZP   (4 bits - destination register OR branch condition)
//   [7:4]   = RS       (4 bits - source register 1)
//   [3:0]   = RT       (4 bits - source register 2)
//   [7:0]   = IMM      (8 bits - immediate value, overlaps RS:RT)
//
// Opcode table:
//   0000 = NOP    - No operation
//   0001 = BRnzp  - Branch if NZP condition matches
//   0010 = CMP    - Compare rs and rt, set NZP register
//   0011 = ADD    - rd = rs + rt
//   0100 = SUB    - rd = rs - rt
//   0101 = MUL    - rd = rs * rt
//   0110 = DIV    - rd = rs / rt
//   0111 = LDR    - rd = Memory[rs]
//   1000 = STR    - Memory[rs] = rt
//   1001 = CONST  - rd = immediate
//   1111 = RET    - Thread execution complete
//
// Control signals generated:
//   reg_write_enable     - Should we write to a register?
//   mem_read_enable      - Should we read from data memory?
//   mem_write_enable     - Should we write to data memory?
//   nzp_write_enable     - Should we update the NZP register?
//   reg_input_mux        - Source of register write (00=ALU, 01=LSU, 10=IMM)
//   alu_arithmetic_mux   - Which ALU operation (00=ADD, 01=SUB, 10=MUL, 11=DIV)
//   alu_output_mux       - ALU mode (0=arithmetic, 1=compare)
//   pc_mux               - PC source (0=PC+1, 1=branch target)
//   ret                  - Thread finished?
// ============================================================================
module decoder (
    input wire clk,
    input wire reset,

    // Execution state from scheduler
    input reg [2:0] core_state,
    // Raw instruction from fetcher
    input reg [15:0] instruction,

    // Decoded instruction fields
    output reg [3:0] decoded_rd_address,   // Destination register address
    output reg [3:0] decoded_rs_address,   // Source register 1 address
    output reg [3:0] decoded_rt_address,   // Source register 2 address
    output reg [2:0] decoded_nzp,          // Branch condition (Negative/Zero/Positive)
    output reg [7:0] decoded_immediate,    // Immediate value

    // Decoded control signals
    output reg decoded_reg_write_enable,
    output reg decoded_mem_read_enable,
    output reg decoded_mem_write_enable,
    output reg decoded_nzp_write_enable,
    output reg [1:0] decoded_reg_input_mux,
    output reg [1:0] decoded_alu_arithmetic_mux,
    output reg decoded_alu_output_mux,
    output reg decoded_pc_mux,

    // Return signal (thread finished)
    output reg decoded_ret
);
    // Opcode definitions
    localparam NOP   = 4'b0000,
        BRnzp = 4'b0001,
        CMP   = 4'b0010,
        ADD   = 4'b0011,
        SUB   = 4'b0100,
        MUL   = 4'b0101,
        DIV   = 4'b0110,
        LDR   = 4'b0111,
        STR   = 4'b1000,
        CONST = 4'b1001,
        RET   = 4'b1111;

    always @(posedge clk) begin
        if (reset) begin
            decoded_rd_address <= 0;
            decoded_rs_address <= 0;
            decoded_rt_address <= 0;
            decoded_immediate <= 0;
            decoded_nzp <= 0;
            decoded_reg_write_enable <= 0;
            decoded_mem_read_enable <= 0;
            decoded_mem_write_enable <= 0;
            decoded_nzp_write_enable <= 0;
            decoded_reg_input_mux <= 0;
            decoded_alu_arithmetic_mux <= 0;
            decoded_alu_output_mux <= 0;
            decoded_pc_mux <= 0;
            decoded_ret <= 0;
        end else begin
            // Decode during DECODE stage
            if (core_state == 3'b010) begin
                // Extract instruction fields
                decoded_rd_address <= instruction[11:8];
                decoded_rs_address <= instruction[7:4];
                decoded_rt_address <= instruction[3:0];
                decoded_immediate  <= instruction[7:0];
                decoded_nzp        <= instruction[11:9];

                // Reset all control signals (set conditionally below)
                decoded_reg_write_enable <= 0;
                decoded_mem_read_enable <= 0;
                decoded_mem_write_enable <= 0;
                decoded_nzp_write_enable <= 0;
                decoded_reg_input_mux <= 0;
                decoded_alu_arithmetic_mux <= 0;
                decoded_alu_output_mux <= 0;
                decoded_pc_mux <= 0;
                decoded_ret <= 0;

                // Set control signals based on opcode
                case (instruction[15:12])
                    NOP: begin
                        // No operation - all signals stay 0
                    end
                    BRnzp: begin
                        decoded_pc_mux <= 1;  // Use branch target for PC
                    end
                    CMP: begin
                        decoded_alu_output_mux <= 1;   // ALU in compare mode
                        decoded_nzp_write_enable <= 1;  // Update NZP register
                    end
                    ADD: begin
                        decoded_reg_write_enable <= 1;
                        decoded_reg_input_mux <= 2'b00;       // Write from ALU
                        decoded_alu_arithmetic_mux <= 2'b00;  // ADD operation
                    end
                    SUB: begin
                        decoded_reg_write_enable <= 1;
                        decoded_reg_input_mux <= 2'b00;
                        decoded_alu_arithmetic_mux <= 2'b01;  // SUB operation
                    end
                    MUL: begin
                        decoded_reg_write_enable <= 1;
                        decoded_reg_input_mux <= 2'b00;
                        decoded_alu_arithmetic_mux <= 2'b10;  // MUL operation
                    end
                    DIV: begin
                        decoded_reg_write_enable <= 1;
                        decoded_reg_input_mux <= 2'b00;
                        decoded_alu_arithmetic_mux <= 2'b11;  // DIV operation
                    end
                    LDR: begin
                        decoded_reg_write_enable <= 1;
                        decoded_reg_input_mux <= 2'b01;  // Write from LSU (memory)
                        decoded_mem_read_enable <= 1;      // Trigger memory read
                    end
                    STR: begin
                        decoded_mem_write_enable <= 1;  // Trigger memory write
                    end
                    CONST: begin
                        decoded_reg_write_enable <= 1;
                        decoded_reg_input_mux <= 2'b10;  // Write immediate value
                    end
                    RET: begin
                        decoded_ret <= 1;  // Signal thread completion
                    end
                endcase
            end
        end
    end
endmodule
