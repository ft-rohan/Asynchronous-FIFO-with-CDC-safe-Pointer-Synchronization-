module async_fifo #(
    parameter width = 4, 
    parameter depth = 4 
)(
    input wire wclk,
    input wire rclk,
    input wire w_en,
    input wire r_en,
    input wire [width-1:0] data_in,
    output wire [width-1:0] data_out, 
    output wire full, 
    output wire empty,
    input wire rst
);

wire [depth-1:0] bin_wptr;   
wire [depth-1:0] bin_rptr; 
wire [depth:0] gray_rptr;    
wire [depth:0] gray_wptr;

// Synchronized pointers (after 2-FF CDC)
wire [depth:0] gray_wptr_sync;  // wptr synced to rclk → for empty detection
wire [depth:0] gray_rptr_sync;  // rptr synced to wclk → for full detection

fifo_memory #(
    .width(width), .depth(depth)
) u_fifo_memory (
    .w_clk  (wclk),
    .w_en   (w_en),
   
    .full   (full),
    .r_ad   (bin_rptr[depth-1:0]),
    .w_ad   (bin_wptr[depth-1:0]),
    .r_data (data_out),
    .w_data (data_in)
);

wptr_generator #(
    .width(depth)
) u_wptr_generator (
    .wclk      (wclk),
    .wnrst     (rst),
    .wen       (w_en),
    .gray_rptr (gray_rptr_sync),   // use SYNCHRONIZED rptr
    .bin_wptr  (bin_wptr),
    .full      (full),
    .gray_wptr (gray_wptr)
);

rptr_generator #(
    .width(depth)
) u_rptr_generator (
    .gray_wptr (gray_wptr_sync),   // use SYNCHRONIZED wptr
    .rclk      (rclk),
    .ren       (r_en),
    .rnrst     (rst),
    .empty     (empty),
    .bin_rptr  (bin_rptr),
    .gray_rptr (gray_rptr)
);

// CDC: rptr (rclk domain) → synced to wclk → for full flag
cdc_sync #(.WIDTH(depth+1)) u_ff_w (
    .clk      (wclk),
    .nrst     (rst),
    .async_in (gray_rptr),        // raw rptr from rclk domain
    .sync_out (gray_rptr_sync)    // safe to use in wclk domain
);

// CDC: wptr (wclk domain) → synced to rclk → for empty flag
cdc_sync #(.WIDTH(depth+1)) u_ff_r (
    .clk      (rclk),
    .nrst     (rst),
    .async_in (gray_wptr),        // raw wptr from wclk domain
    .sync_out (gray_wptr_sync)    // safe to use in rclk domain
);

endmodule