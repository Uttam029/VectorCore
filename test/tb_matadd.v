`timescale 1ns/1ns

// ============================================================================
// MATRIX ADDITION TESTBENCH
// ============================================================================
// Simulates the GPU executing a matrix addition kernel: C = A + B
// A = [0, 1, 2, 3, 4, 5, 6, 7]
// B = [0, 1, 2, 3, 4, 5, 6, 7]
// Expected C = [0, 2, 4, 6, 8, 10, 12, 14]
// Uses 8 threads (2 blocks × 4 threads per block on 2 cores)
// ============================================================================
module tb_matadd;
    // Parameters (must match GPU instantiation)
    parameter DATA_MEM_NUM_CHANNELS = 4;
    parameter PROGRAM_MEM_NUM_CHANNELS = 1;

    // Clock and reset
    reg clk = 0;
    reg reset = 0;

    // Kernel control
    reg start = 0;
    wire done;

    // DCR interface
    reg device_control_write_enable = 0;
    reg [7:0] device_control_data = 0;

    // Program memory interface (flattened, 1 channel × 8-bit addr, 16-bit data)
    reg [0:0] program_mem_read_ready;
    reg [15:0] program_mem_read_data;     // 1 channel × 16 bits
    wire [0:0] program_mem_read_valid;
    wire [7:0] program_mem_read_address;  // 1 channel × 8 bits

    // Data memory interface (flattened, 4 channels × 8-bit addr/data)
    reg [3:0] data_mem_read_ready;
    reg [31:0] data_mem_read_data;        // 4 channels × 8 bits = 32 bits
    wire [3:0] data_mem_read_valid;
    wire [31:0] data_mem_read_address;    // 4 channels × 8 bits = 32 bits
    reg [3:0] data_mem_write_ready;
    wire [3:0] data_mem_write_valid;
    wire [31:0] data_mem_write_address;   // 4 channels × 8 bits = 32 bits
    wire [31:0] data_mem_write_data;      // 4 channels × 8 bits = 32 bits

    // Internal memory arrays
    reg [15:0] program_memory [0:255];
    reg [7:0] data_memory [0:255];

    // GPU instance
    gpu #(
        .DATA_MEM_ADDR_BITS(8),
        .DATA_MEM_DATA_BITS(8),
        .DATA_MEM_NUM_CHANNELS(4),
        .PROGRAM_MEM_ADDR_BITS(8),
        .PROGRAM_MEM_DATA_BITS(16),
        .PROGRAM_MEM_NUM_CHANNELS(1),
        .NUM_CORES(2),
        .THREADS_PER_BLOCK(4)
    ) gpu_inst (
        .clk(clk),
        .reset(reset),
        .start(start),
        .done(done),
        .device_control_write_enable(device_control_write_enable),
        .device_control_data(device_control_data),
        .program_mem_read_valid(program_mem_read_valid),
        .program_mem_read_address(program_mem_read_address),
        .program_mem_read_ready(program_mem_read_ready),
        .program_mem_read_data(program_mem_read_data),
        .data_mem_read_valid(data_mem_read_valid),
        .data_mem_read_address(data_mem_read_address),
        .data_mem_read_ready(data_mem_read_ready),
        .data_mem_read_data(data_mem_read_data),
        .data_mem_write_valid(data_mem_write_valid),
        .data_mem_write_address(data_mem_write_address),
        .data_mem_write_data(data_mem_write_data),
        .data_mem_write_ready(data_mem_write_ready)
    );

    // Clock generation: 25MHz (40ns period)
    always #20 clk = ~clk;

    // ================================================================
    // Memory Interface Simulation
    // ================================================================
    // sv2v flattens unpacked arrays:
    //   Channel 0 uses bits [7:0], Channel 1 uses [15:8], etc.
    // ================================================================
    integer ch;
    reg [7:0] addr;

    always @(posedge clk) begin
        // Program memory read (1 channel)
        if (program_mem_read_valid[0]) begin
            addr = program_mem_read_address[7:0];
            program_mem_read_data[15:0] <= program_memory[addr];
            program_mem_read_ready[0] <= 1;
        end else begin
            program_mem_read_ready[0] <= 0;
        end

        // Data memory read (4 channels)
        for (ch = 0; ch < 4; ch = ch + 1) begin
            if (data_mem_read_valid[ch]) begin
                addr = data_mem_read_address[ch*8 +: 8];
                data_mem_read_data[ch*8 +: 8] <= data_memory[addr];
                data_mem_read_ready[ch] <= 1;
            end else begin
                data_mem_read_ready[ch] <= 0;
            end
        end

        // Data memory write (4 channels)
        for (ch = 0; ch < 4; ch = ch + 1) begin
            if (data_mem_write_valid[ch]) begin
                addr = data_mem_write_address[ch*8 +: 8];
                data_memory[addr] <= data_mem_write_data[ch*8 +: 8];
                data_mem_write_ready[ch] <= 1;
            end else begin
                data_mem_write_ready[ch] <= 0;
            end
        end
    end

    // ================================================================
    // Main Simulation
    // ================================================================
    integer cycle_count;
    integer i;
    integer pass;

    initial begin
        // Initialize all memory
        for (i = 0; i < 256; i = i + 1) begin
            program_memory[i] = 16'h0000;
            data_memory[i] = 8'h00;
        end

        // Initialize interface signals
        program_mem_read_ready = 0;
        program_mem_read_data = 0;
        data_mem_read_ready = 0;
        data_mem_read_data = 0;
        data_mem_write_ready = 0;

        // ================================================================
        // Load Matrix Addition Kernel
        // ================================================================
        program_memory[0]  = 16'b0101000011011110; // MUL R0, %blockIdx, %blockDim
        program_memory[1]  = 16'b0011000000001111; // ADD R0, R0, %threadIdx      ; i = blockIdx * blockDim + threadIdx
        program_memory[2]  = 16'b1001000100000000; // CONST R1, #0                ; baseA
        program_memory[3]  = 16'b1001001000001000; // CONST R2, #8                ; baseB
        program_memory[4]  = 16'b1001001100010000; // CONST R3, #16               ; baseC
        program_memory[5]  = 16'b0011010000010000; // ADD R4, R1, R0              ; addr(A[i])
        program_memory[6]  = 16'b0111010001000000; // LDR R4, R4                  ; load A[i]
        program_memory[7]  = 16'b0011010100100000; // ADD R5, R2, R0              ; addr(B[i])
        program_memory[8]  = 16'b0111010101010000; // LDR R5, R5                  ; load B[i]
        program_memory[9]  = 16'b0011011001000101; // ADD R6, R4, R5              ; C[i] = A[i] + B[i]
        program_memory[10] = 16'b0011011100110000; // ADD R7, R3, R0              ; addr(C[i])
        program_memory[11] = 16'b1000000001110110; // STR R7, R6                  ; store C[i]
        program_memory[12] = 16'b1111000000000000; // RET

        // ================================================================
        // Load Data: A = [0..7], B = [0..7]
        // ================================================================
        data_memory[0] = 0;  data_memory[1] = 1;  data_memory[2] = 2;  data_memory[3] = 3;
        data_memory[4] = 4;  data_memory[5] = 5;  data_memory[6] = 6;  data_memory[7] = 7;
        data_memory[8]  = 0;  data_memory[9]  = 1;  data_memory[10] = 2;  data_memory[11] = 3;
        data_memory[12] = 4;  data_memory[13] = 5;  data_memory[14] = 6;  data_memory[15] = 7;

        // ================================================================
        // Display
        // ================================================================
        $display("");
        $display("============================================================");
        $display("  VectorCore: Matrix Addition Simulation");
        $display("  C = A + B  where A = B = [0, 1, 2, 3, 4, 5, 6, 7]");
        $display("  8 threads, 2 cores, 4 threads/block");
        $display("============================================================");
        $display("");
        $display("--- Initial Data Memory ---");
        $display("Matrix A (addr 0-7):  %0d %0d %0d %0d %0d %0d %0d %0d",
            data_memory[0], data_memory[1], data_memory[2], data_memory[3],
            data_memory[4], data_memory[5], data_memory[6], data_memory[7]);
        $display("Matrix B (addr 8-15): %0d %0d %0d %0d %0d %0d %0d %0d",
            data_memory[8], data_memory[9], data_memory[10], data_memory[11],
            data_memory[12], data_memory[13], data_memory[14], data_memory[15]);
        $display("");

        // ================================================================
        // Reset GPU
        // ================================================================
        reset = 1;
        @(posedge clk);
        @(posedge clk);
        reset = 0;

        // ================================================================
        // Configure DCR: Set thread count = 8
        // Need extra cycles for DCR value to propagate through the design
        // ================================================================
        device_control_write_enable = 1;
        device_control_data = 8;
        @(posedge clk);
        @(posedge clk);  // Extra cycle for DCR latch to propagate
        device_control_write_enable = 0;
        @(posedge clk);  // One more cycle to ensure thread_count is stable

        // ================================================================
        // Start Kernel
        // ================================================================
        $display(">>> Launching kernel with 8 threads...");
        $display("    thread_count=%0d, total_blocks=%0d",
            gpu_inst.thread_count,
            gpu_inst.dispatch_instance.total_blocks);
        $display("");
        start = 1;

        // Wait for dispatcher to initialize
        repeat(3) @(posedge clk);

        // Run until done or timeout (use !== to handle X/Z values)
        cycle_count = 0;
        while (done !== 1'b1 && cycle_count < 10000) begin
            @(posedge clk);
            cycle_count = cycle_count + 1;
        end

        // Wait for final writes
        repeat(10) @(posedge clk);

        // ================================================================
        // Results
        // ================================================================
        $display("============================================================");
        $display("  RESULTS (completed in %0d cycles)", cycle_count);
        $display("============================================================");
        $display("");
        $display("--- Final Data Memory ---");
        $display("Matrix A (addr 0-7):   %0d %0d %0d %0d %0d %0d %0d %0d",
            data_memory[0], data_memory[1], data_memory[2], data_memory[3],
            data_memory[4], data_memory[5], data_memory[6], data_memory[7]);
        $display("Matrix B (addr 8-15):  %0d %0d %0d %0d %0d %0d %0d %0d",
            data_memory[8], data_memory[9], data_memory[10], data_memory[11],
            data_memory[12], data_memory[13], data_memory[14], data_memory[15]);
        $display("Matrix C (addr 16-23): %0d %0d %0d %0d %0d %0d %0d %0d",
            data_memory[16], data_memory[17], data_memory[18], data_memory[19],
            data_memory[20], data_memory[21], data_memory[22], data_memory[23]);
        $display("");

        // ================================================================
        // Verify
        // ================================================================
        pass = 1;
        for (i = 0; i < 8; i = i + 1) begin
            if (data_memory[16+i] !== (data_memory[i] + data_memory[8+i])) begin
                $display("FAIL: C[%0d] = %0d, expected %0d", i, data_memory[16+i], data_memory[i] + data_memory[8+i]);
                pass = 0;
            end
        end

        if (pass) begin
            $display("=========================================");
            $display("  >>> ALL TESTS PASSED! <<<");
            $display("=========================================");
            $display("  Expected: [0, 2, 4, 6, 8, 10, 12, 14]");
            $display("  Got:      [%0d, %0d, %0d, %0d, %0d, %0d, %0d, %0d]",
                data_memory[16], data_memory[17], data_memory[18], data_memory[19],
                data_memory[20], data_memory[21], data_memory[22], data_memory[23]);
        end else begin
            $display(">>> SOME TESTS FAILED <<<");
        end

        $display("");
        $finish;
    end

    // Safety timeout
    initial begin
        #2000000;
        $display("TIMEOUT: Simulation exceeded limit");
        $finish;
    end

    // Waveform Generation
    initial begin
        $dumpfile("docs/matadd_waveform.vcd");
        $dumpvars(0, tb_matadd);
    end
endmodule
