`default_nettype none
`timescale 1ns/1ns

// ============================================================================
// LOAD-STORE UNIT (LSU)
// ============================================================================
// Purpose: Handles asynchronous memory load (LDR) and store (STR) operations.
// Each thread in each core has its own dedicated LSU.
//
// LDR instruction flow:
//   REQUEST stage → Send read request (address = rs)
//   WAIT stage    → Wait for memory controller response
//   Done          → lsu_out = data from memory
//
// STR instruction flow:
//   REQUEST stage → Send write request (address = rs, data = rt)
//   WAIT stage    → Wait for memory controller acknowledgment
//
// The LSU communicates with the data memory controller which arbitrates
// access to the limited-bandwidth external memory.
// ============================================================================
module lsu (
    input wire clk,
    input wire reset,
    input wire enable,  // Disabled when block has fewer threads than block size

    // Execution state from scheduler
    input reg [2:0] core_state,

    // Control signals from decoder
    input reg decoded_mem_read_enable,   // LDR instruction
    input reg decoded_mem_write_enable,  // STR instruction

    // Register values (operands)
    input reg [7:0] rs,  // Memory address (for both LDR and STR)
    input reg [7:0] rt,  // Write data (for STR only)

    // Data memory interface (to memory controller)
    output reg mem_read_valid,
    output reg [7:0] mem_read_address,
    input reg mem_read_ready,
    input reg [7:0] mem_read_data,
    output reg mem_write_valid,
    output reg [7:0] mem_write_address,
    output reg [7:0] mem_write_data,
    input reg mem_write_ready,

    // LSU outputs
    output reg [1:0] lsu_state,  // Current state (scheduler checks this)
    output reg [7:0] lsu_out     // Loaded data (fed back to register file)
);
    // LSU state machine
    localparam IDLE = 2'b00, REQUESTING = 2'b01, WAITING = 2'b10, DONE = 2'b11;

    always @(posedge clk) begin
        if (reset) begin
            lsu_state <= IDLE;
            lsu_out <= 0;
            mem_read_valid <= 0;
            mem_read_address <= 0;
            mem_write_valid <= 0;
            mem_write_address <= 0;
            mem_write_data <= 0;
        end else if (enable) begin
            // ---- LDR (Load from memory) ----
            if (decoded_mem_read_enable) begin
                case (lsu_state)
                    IDLE: begin
                        // Start requesting when core enters REQUEST stage
                        if (core_state == 3'b011) begin
                            lsu_state <= REQUESTING;
                        end
                    end
                    REQUESTING: begin
                        // Send read request to memory controller
                        mem_read_valid <= 1;
                        mem_read_address <= rs;
                        lsu_state <= WAITING;
                    end
                    WAITING: begin
                        // Wait for memory controller to return data
                        if (mem_read_ready == 1) begin
                            mem_read_valid <= 0;
                            lsu_out <= mem_read_data;
                            lsu_state <= DONE;
                        end
                    end
                    DONE: begin
                        // Reset when core reaches UPDATE stage
                        if (core_state == 3'b110) begin
                            lsu_state <= IDLE;
                        end
                    end
                endcase
            end

            // ---- STR (Store to memory) ----
            if (decoded_mem_write_enable) begin
                case (lsu_state)
                    IDLE: begin
                        // Start requesting when core enters REQUEST stage
                        if (core_state == 3'b011) begin
                            lsu_state <= REQUESTING;
                        end
                    end
                    REQUESTING: begin
                        // Send write request to memory controller
                        mem_write_valid <= 1;
                        mem_write_address <= rs;
                        mem_write_data <= rt;
                        lsu_state <= WAITING;
                    end
                    WAITING: begin
                        // Wait for memory controller acknowledgment
                        if (mem_write_ready) begin
                            mem_write_valid <= 0;
                            lsu_state <= DONE;
                        end
                    end
                    DONE: begin
                        // Reset when core reaches UPDATE stage
                        if (core_state == 3'b110) begin
                            lsu_state <= IDLE;
                        end
                    end
                endcase
            end
        end
    end
endmodule
