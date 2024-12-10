module filter #( parameter DATA_WIDTH=32 ) (
    input clk_in,
    input rst_in,

    input [DATA_WIDTH-1:0] sample_in,
    input sample_valid_in,

    output [DATA_WIDTH+COEFF_WIDTH-1:0] sample_out,
    output sample_valid_out
);

    localparam int FRACTION_WIDTH = 16;
    localparam int COEFF_WIDTH = FRACTION_WIDTH + 2; // Max coeff int size is 1 bit + sign
    localparam logic signed [COEFF_WIDTH-1:0] A_1 = 123670;
    localparam logic signed [COEFF_WIDTH-1:0] A_2 = -58148;

    localparam logic signed [COEFF_WIDTH-1:0] B_0 = 3693;
    localparam logic signed [COEFF_WIDTH-1:0] B_1 = 0;
    localparam logic signed [COEFF_WIDTH-1:0] B_2 = -3693;

    logic [4:0][DATA_WIDTH-1:0] in_sample_cache;
    logic signed [4:0][DATA_WIDTH+COEFF_WIDTH-1:0] out_sample_cache;

    logic [1:0] coefficients_passed;
    logic [$clog2(4)-1:0] stage;

    assign sample_valid_out = (stage == 3);
    assign sample_out = out_sample_cache[0];

    logic signed [1:0][DATA_WIDTH+COEFF_WIDTH-1:0] b_muls;
    logic signed [1:0][2*DATA_WIDTH+COEFF_WIDTH-1:0] a_muls;
    logic signed [1:0][DATA_WIDTH+COEFF_WIDTH-1:0] a_shifts;

    always_comb begin
        b_muls[0] = B_1 * in_sample_cache[1];
        b_muls[1] = B_2 * in_sample_cache[2];

        a_muls[0] = A_1 * out_sample_cache[1];
        a_muls[1] = A_2 * out_sample_cache[2];

        a_shifts[0] = a_muls[0] >>> FRACTION_WIDTH;
        a_shifts[1] = a_muls[1] >>> FRACTION_WIDTH;
    end

    always_ff @ (posedge clk_in) begin
        if (rst_in) begin
            stage <= '0;
            coefficients_passed <= '0;

            in_sample_cache <= '0;
            out_sample_cache <= '0;
        end else begin
            if (sample_valid_in) begin
                in_sample_cache <= {in_sample_cache, sample_in};
                out_sample_cache[4:1] <= out_sample_cache[3:0];
                out_sample_cache[0] <= B_0 * sample_in;
                stage <= 1;
            end else if (stage == 1) begin
                if (coefficients_passed[0]) begin
                    out_sample_cache[0] <= out_sample_cache[0] + b_muls[0] + a_shifts[0];
                end
                stage <= 2;
            end else if (stage == 2) begin
                if (coefficients_passed[1]) begin
                    out_sample_cache[0] <= out_sample_cache[0] + b_muls[1] + a_shifts[1];
                end
                stage <= 3;
            end else if (stage == 3) begin
                stage <= 0;
                coefficients_passed <= {coefficients_passed, 1'b1};
            end
        end
    end
endmodule
