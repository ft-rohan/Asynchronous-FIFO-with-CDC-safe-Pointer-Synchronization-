module rptr_generator #(
    parameter width = 4
)(
    input wire [width :0] gray_wptr,
    input wire  rclk,
    input wire ren, 
    input wire rnrst,
    output reg empty, 
    output wire [width-1:0] bin_rptr,
    output reg [width :0 ] gray_rptr
    );
    
    reg [width:0] ptr ; 
    
    wire [width:0]ptr_next = ptr + (ren & !empty); 
    wire [width:0]gray_ptr_next = ptr_next ^ (ptr_next>>1); 
    
   always @(posedge rclk or negedge rnrst )begin 
   
   if(!rnrst)begin 
    
        ptr<=0; 
        empty<= 1'b1; 
        gray_rptr <= 0; 
        
   end 
   else begin 
        ptr<=ptr_next; 
        gray_rptr<=gray_ptr_next;
        empty <= (gray_wptr==gray_ptr_next);
   end 
   
   end 
 
assign  bin_rptr= ptr[width-1:0];   
endmodule
