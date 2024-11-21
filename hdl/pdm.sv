`default_nettype none `timescale 1 ns / 1 ps

module pdm #(
    parameter int NBITS = 16
) (
    input  wire              clk_in,
    input  wire  [NBITS-1:0] d_in,
    input  wire              rst_in,
    output logic             d_out
);

    localparam integer MAX = 2 ** NBITS - 1;
    logic [NBITS-1:0] din_reg;
    logic [NBITS-1:0] error_0;
    logic [NBITS-1:0] error_1;
    logic [NBITS-1:0] error;

    always @(posedge clk_in) begin
        if (rst_in == 1'b1) begin
            d_out   <= 0;
            error   <= 0;
            error_0 <= 0;
            error_1 <= 0;
        end else begin
            if (din_reg >= error) begin
                d_out <= 1;
                error <= error_1;
            end else begin
                d_out <= 0;
                error <= error_0;
            end
            din_reg <= d_in;
            error_1 <= error + MAX - din_reg;
            error_0 <= error - din_reg;
        end
    end

endmodule
`default_nettype wire
