`default_nettype wire
module counter(
    input wire clk_in,
    input wire rst_in,
    input wire [31:0] period_in,
    output logic [31:0] count_out
              );

    logic [31:0] new_val;
    always_comb begin
        if (rst_in == 1'b1 || count_out == (period_in - 1)) begin
            new_val = 0;
        end else begin
            new_val = count_out + 1;
        end
    end

    always_ff @(posedge clk_in) begin
        count_out <= new_val;
    end
endmodule
`default_nettype none
