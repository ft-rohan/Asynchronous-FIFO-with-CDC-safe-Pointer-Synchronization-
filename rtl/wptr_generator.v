module wptr_generator#(
    parameter width = 4
)(
    input wire wclk, wnrst, wen, 
    input wire [width:0] gray_rptr, 
    
    output wire [width-1:0] bin_wptr, 
    output reg full, 
    output reg [width:0] gray_wptr
);
reg [width:0]w_ptr ; 
wire [width : 0 ]w_ptr_next = w_ptr + (wen & !full) ;
wire [width :0]g_w_ptr = w_ptr_next ^ (w_ptr_next >> 1);

wire wfull = (g_w_ptr == {~gray_rptr[width:width-1],gray_rptr[width-2:0]});

always@(posedge wclk or negedge wnrst)begin 

if(!wnrst)begin 
    w_ptr <= 0; 
    gray_wptr<=0; 
    full<=0; 
    end
else begin 
    w_ptr<=w_ptr_next; 
    gray_wptr<= g_w_ptr; 
    full <= wfull; 
end

end

assign bin_wptr = w_ptr[width-1 :0 ]; 

endmodule