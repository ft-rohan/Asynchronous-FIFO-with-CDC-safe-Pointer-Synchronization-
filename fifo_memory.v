`timescale 1ns / 1ps


module fifo_memory#(
parameter width = 8, parameter depth =4
)(
    input wire w_clk,
    input wire w_en,
    input wire full,
    
    input wire [depth-1 :0] r_ad,
    input wire [depth-1 :0] w_ad,
    output wire [width-1 :0] r_data,
    input wire [width-1 :0] w_data
    );
    localparam depth_1 = 1<<depth;
    reg [width-1:0] memory [0:depth_1-1];
    
    always@(posedge w_clk)
    begin 
    if(w_en && !full) memory[w_ad] <= w_data; 
    
    end 
    assign r_data = memory[r_ad];
endmodule
