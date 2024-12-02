`timescale 1ns / 1ps
`default_nettype none

module pipeline
	#(
	 parameter STAGES = 1,
     parameter WIDTH = 32
	 )
	(
	 input wire										 clk,
     input wire rst,
     input wire [WIDTH-1:0] din,
	 input wire [WIDTH-1:0] dout
	 );

     logic [WIDTH-1:0] stages [STAGES-1:0];
     
    always_ff @(posedge clk) begin
        stages[0] <= din;
        for (int i = 1; i < STAGES; i = i + 1) begin
            stages[i] <= stages[i-1];
        end
    end
     
     assign dout = stages[STAGES-1];

endmodule