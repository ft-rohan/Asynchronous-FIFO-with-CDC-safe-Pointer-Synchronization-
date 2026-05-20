`timescale 1ns / 1ps

module tb_async_fifo;

parameter WIDTH = 4;
parameter DEPTH = 4;   // FIFO depth parameter (2^4 = 16 entries)

reg              wclk, rclk, rst;
reg              w_en, r_en;
reg  [WIDTH-1:0] data_in;
wire [WIDTH-1:0] data_out;
wire              full, empty;

integer pass_count, fail_count;

// Instantiate the Device Under Test (DUT)
async_fifo #(
    .width(WIDTH),
    .depth(DEPTH)
) dut (
    .wclk    (wclk),
    .rclk    (rclk),
    .rst     (rst),
    .w_en    (w_en),
    .r_en    (r_en),
    .data_in (data_in),
    .data_out(data_out),
    .full    (full),
    .empty   (empty)
);

// ── Clock Generation ─────────────────────────────────────────
// wclk = 100 MHz (10ns period)
initial wclk = 0;
always #5 wclk = ~wclk;

// rclk = 75 MHz (~13.33ns period)
initial rclk = 0;
always #6.67 rclk = ~rclk;

// ── Stimulus Blocks ──────────────────────────────────────────
initial begin
    pass_count = 0;
    fail_count = 0;

    // ── Reset Phase (Active-Low) ─────────────────────────────
    rst     = 0;
    w_en    = 0;
    r_en    = 0;
    data_in = 0;
    #50;            // Hold reset for 5 wclk cycles
    rst     = 1;    // Release reset
    #30;            // Settle time for CDC flags

    $display("\n===== TEST: Write 4 words, read back and verify =====");

    // ── Burst Write 4 Words (wclk Domain) ────────────────────
    @(posedge wclk); #1; w_en = 1; data_in = 4'hA; $display("[WRITE] data_in = 0xA");
    @(posedge wclk); #1; w_en = 1; data_in = 4'hB; $display("[WRITE] data_in = 0xB");
    @(posedge wclk); #1; w_en = 1; data_in = 4'hC; $display("[WRITE] data_in = 0xC");
    @(posedge wclk); #1; w_en = 1; data_in = 4'hD; $display("[WRITE] data_in = 0xD");
    @(posedge wclk); #1; w_en = 0; data_in = 0;   // Clean teardown

    // ── Level-Sensitive Flag Wait (Prevents Deadlocks) ──────
    // If empty drops low before execution reaches here, this won't hang!
    while (empty) begin
        @(posedge rclk);
    end
    #40; // Additional small guard band for cross-domain stability

    // ── Synchronous Burst Read & Verification (rclk Domain) ──
    // Step 1: Assert read enable cleanly right after the clock edge
    @(posedge rclk); #1; 
    r_en = 1;

    // Word 1: Let the pointer increment, then evaluate active bus data
    @(posedge rclk); #1;
    if (data_out === 4'hA) begin
        $display("[PASS]  data_out = 0x%h  (expected 0xA)", data_out);
        pass_count = pass_count + 1;
    end else begin
        $display("[FAIL]  data_out = 0x%h  (expected 0xA)", data_out);
        fail_count = fail_count + 1;
    end

    // Word 2
    @(posedge rclk); #1;
    if (data_out === 4'hB) begin
        $display("[PASS]  data_out = 0x%h  (expected 0xB)", data_out);
        pass_count = pass_count + 1;
    end else begin
        $display("[FAIL]  data_out = 0x%h  (expected 0xB)", data_out);
        fail_count = fail_count + 1;
    end

    // Word 3
    @(posedge rclk); #1;
    if (data_out === 4'hC) begin
        $display("[PASS]  data_out = 0x%h  (expected 0xC)", data_out);
        pass_count = pass_count + 1;
    end else begin
        $display("[FAIL]  data_out = 0x%h  (expected 0xC)", data_out);
        fail_count = fail_count + 1;
    end

    // Word 4
    @(posedge rclk); #1;
    if (data_out === 4'hD) begin
        $display("[PASS]  data_out = 0x%h  (expected 0xD)", data_out);
        pass_count = pass_count + 1;
    end else begin
        $display("[FAIL]  data_out = 0x%h  (expected 0xD)", data_out);
        fail_count = fail_count + 1;
    end

    // Step 2: Clear read enable after finishing transaction group
    r_en = 0;

    // ── Post-Drain Status Verification ───────────────────────
    #80; // Wait for pointers to synchronize backward
    if (empty) begin
        $display("[PASS]  FIFO empty after drain.");
        pass_count = pass_count + 1;
    end else begin
        $display("[FAIL]  FIFO not empty after drain.");
        fail_count = fail_count + 1;
    end

    // ── Final Summary Scoreboard ─────────────────────────────
    $display("\n========================================");
    $display("  RESULTS: %0d PASS | %0d FAIL", pass_count, fail_count);
    if (fail_count == 0)
        $display("  ALL CHECKS PASSED");
    else
        $display("  *** %0d CHECK(S) FAILED ***", fail_count);
    $display("========================================\n");
    
    $finish;
end

endmodule