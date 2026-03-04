`default_nettype none
`timescale 1ns/1ns

// ============================================================================
// DEVICE CONTROL REGISTER (DCR)
// ============================================================================
// Purpose: Stores high-level kernel configuration settings.
// In this minimal GPU, the DCR only stores the total number of threads
// to launch for the current kernel execution.
//
// How it works:
//   - The host writes the thread count before launching the kernel
//   - The dispatcher reads this value to know how many threads to distribute
// ============================================================================
module dcr (
    input wire clk,
    input wire reset,

    // Host interface - write thread count before kernel launch
    input wire device_control_write_enable,
    input wire [7:0] device_control_data,

    // Output to dispatcher
    output wire [7:0] thread_count
);
    // Internal register to store the configuration
    reg [7:0] device_control_register;
    assign thread_count = device_control_register[7:0];

    always @(posedge clk) begin
        if (reset) begin
            device_control_register <= 8'b0;
        end else begin
            if (device_control_write_enable) begin
                device_control_register <= device_control_data;
            end
        end
    end
endmodule
