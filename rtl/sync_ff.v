module cdc_sync #(parameter WIDTH = 5)(
    input  wire             clk, nrst,   //Destination clock 
    input  wire [WIDTH-1:0] async_in,    //Gray Code Pointer from source domain 
    output wire [WIDTH-1:0] sync_out
);
    // ASYNC_REG: Xilinx attribute - critical, do not remove!
    (* ASYNC_REG = "TRUE" *) reg [WIDTH-1:0] ff1, ff2;

    always @(posedge clk or negedge nrst)
        if (!nrst) {ff2, ff1} <= 0;
        else        {ff2, ff1} <= {ff1, async_in};
    // ff1 may go metastable - ff2 is always stable
    assign sync_out = ff2;
endmodule