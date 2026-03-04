`default_nettype none
`timescale 1ns/1ns

// ============================================================================
// MEMORY CONTROLLER (Arbiter)
// ============================================================================
// Purpose: Arbitrates memory access between N consumers (LSUs or Fetchers)
// and M external memory channels with limited bandwidth.
//
// Why it's needed:
//   - A GPU has many threads, each with its own LSU wanting memory access
//   - External memory has limited bandwidth (fixed number of channels)
//   - The controller queues and schedules requests fairly
// Channel state machine (per channel):
//   IDLE           → Scanning for pending requests
//   READ_WAITING   → Waiting for memory read response
//   WRITE_WAITING  → Waiting for memory write acknowledgment
//   READ_RELAYING  → Sending read data back to consumer
//   WRITE_RELAYING → Sending write ack back to consumer
//
// Parameters:
//   NUM_CONSUMERS = Number of LSUs/Fetchers sharing this controller
//   NUM_CHANNELS  = Number of concurrent memory access channels
//   WRITE_ENABLE  = 0 for program memory (read-only), 1 for data memory
// ============================================================================
module controller #(
    parameter ADDR_BITS = 8,
    parameter DATA_BITS = 16,
    parameter NUM_CONSUMERS = 4,
    parameter NUM_CHANNELS = 1,
    parameter WRITE_ENABLE = 1
) (
    input wire clk,
    input wire reset,

    // Consumer interface (from Fetchers or LSUs)
    input reg [NUM_CONSUMERS-1:0] consumer_read_valid,
    input reg [ADDR_BITS-1:0] consumer_read_address [NUM_CONSUMERS-1:0],
    output reg [NUM_CONSUMERS-1:0] consumer_read_ready,
    output reg [DATA_BITS-1:0] consumer_read_data [NUM_CONSUMERS-1:0],
    input reg [NUM_CONSUMERS-1:0] consumer_write_valid,
    input reg [ADDR_BITS-1:0] consumer_write_address [NUM_CONSUMERS-1:0],
    input reg [DATA_BITS-1:0] consumer_write_data [NUM_CONSUMERS-1:0],
    output reg [NUM_CONSUMERS-1:0] consumer_write_ready,

    // External memory interface
    output reg [NUM_CHANNELS-1:0] mem_read_valid,
    output reg [ADDR_BITS-1:0] mem_read_address [NUM_CHANNELS-1:0],
    input reg [NUM_CHANNELS-1:0] mem_read_ready,
    input reg [DATA_BITS-1:0] mem_read_data [NUM_CHANNELS-1:0],
    output reg [NUM_CHANNELS-1:0] mem_write_valid,
    output reg [ADDR_BITS-1:0] mem_write_address [NUM_CHANNELS-1:0],
    output reg [DATA_BITS-1:0] mem_write_data [NUM_CHANNELS-1:0],
    input reg [NUM_CHANNELS-1:0] mem_write_ready
);
    // Channel state encoding
    localparam IDLE = 3'b000,
        READ_WAITING = 3'b010,
        WRITE_WAITING = 3'b011,
        READ_RELAYING = 3'b100,
        WRITE_RELAYING = 3'b101;

    // Per-channel tracking
    reg [2:0] controller_state [NUM_CHANNELS-1:0];
    reg [$clog2(NUM_CONSUMERS)-1:0] current_consumer [NUM_CHANNELS-1:0];
    // Prevents multiple channels from picking up the same consumer's request
    reg [NUM_CONSUMERS-1:0] channel_serving_consumer;

    always @(posedge clk) begin
        if (reset) begin
            mem_read_valid <= 0;
            mem_read_address <= 0;

            mem_write_valid <= 0;
            mem_write_address <= 0;
            mem_write_data <= 0;

            consumer_read_ready <= 0;
            consumer_read_data <= 0;
            consumer_write_ready <= 0;

            current_consumer <= 0;
            controller_state <= 0;

            channel_serving_consumer = 0;
        end else begin
            // Each channel operates independently and concurrently
            for (int i = 0; i < NUM_CHANNELS; i = i + 1) begin
                case (controller_state[i])
                    IDLE: begin
                        // Scan through consumers looking for pending requests
                        // Using 'found' flag instead of 'break' for iverilog compatibility
                        reg found;
                        found = 0;
                        for (int j = 0; j < NUM_CONSUMERS; j = j + 1) begin
                            if (!found) begin
                                // Check for pending READ request
                                if (consumer_read_valid[j] && !channel_serving_consumer[j]) begin
                                    channel_serving_consumer[j] = 1;
                                    current_consumer[i] <= j;

                                    // Forward read request to external memory
                                    mem_read_valid[i] <= 1;
                                    mem_read_address[i] <= consumer_read_address[j];
                                    controller_state[i] <= READ_WAITING;
                                    found = 1;  // Only pick up one request per cycle
                                end
                                // Check for pending WRITE request
                                else if (consumer_write_valid[j] && !channel_serving_consumer[j]) begin
                                    channel_serving_consumer[j] = 1;
                                    current_consumer[i] <= j;

                                    // Forward write request to external memory
                                    mem_write_valid[i] <= 1;
                                    mem_write_address[i] <= consumer_write_address[j];
                                    mem_write_data[i] <= consumer_write_data[j];
                                    controller_state[i] <= WRITE_WAITING;
                                    found = 1;
                                end
                            end
                        end
                    end
                    READ_WAITING: begin
                        // Wait for external memory to return read data
                        if (mem_read_ready[i]) begin
                            mem_read_valid[i] <= 0;
                            consumer_read_ready[current_consumer[i]] <= 1;
                            consumer_read_data[current_consumer[i]] <= mem_read_data[i];
                            controller_state[i] <= READ_RELAYING;
                        end
                    end
                    WRITE_WAITING: begin
                        // Wait for external memory to acknowledge write
                        if (mem_write_ready[i]) begin
                            mem_write_valid[i] <= 0;
                            consumer_write_ready[current_consumer[i]] <= 1;
                            controller_state[i] <= WRITE_RELAYING;
                        end
                    end
                    READ_RELAYING: begin
                        // Wait for consumer to acknowledge it received the data
                        if (!consumer_read_valid[current_consumer[i]]) begin
                            channel_serving_consumer[current_consumer[i]] = 0;
                            consumer_read_ready[current_consumer[i]] <= 0;
                            controller_state[i] <= IDLE;
                        end
                    end
                    WRITE_RELAYING: begin
                        // Wait for consumer to acknowledge write completion
                        if (!consumer_write_valid[current_consumer[i]]) begin
                            channel_serving_consumer[current_consumer[i]] = 0;
                            consumer_write_ready[current_consumer[i]] <= 0;
                            controller_state[i] <= IDLE;
                        end
                    end
                endcase
            end
        end
    end
endmodule
