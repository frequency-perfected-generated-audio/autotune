`default_nettype none
module fp_div #(
    parameter WIDTH = 42,
    parameter FRACTION_WIDTH = 10,
    parameter NUM_STAGES = 8
) (
    input wire clk_in,
    input wire rst_in,

    input wire [WIDTH-FRACTION_WIDTH-1:0] dividend_in,
    input wire [WIDTH-FRACTION_WIDTH-1:0] divisor_in,
    input wire valid_in,

    output logic [FRACTION_WIDTH:0] quotient_out,
    output logic valid_out,
    output logic err_out,
    output logic busy
);
  // Save first/last stage to register inputs/outputs
  localparam int unsigned NUM_WORKING_STAGES = NUM_STAGES-2;

  // Need FRACTION_WIDTH + 1 cycles ordinarily, so perform all stage
  // calculations with that in mind
  localparam int unsigned BITS_PER_STAGE = ((FRACTION_WIDTH) / NUM_WORKING_STAGES) + 1; // Jank ceiling
  localparam int unsigned STAGE_OVERFLOW = (FRACTION_WIDTH + 1) - (NUM_WORKING_STAGES-1) * BITS_PER_STAGE;

  // control signals
  logic [$clog2(WIDTH+1)-1:0] cycle_count;

  logic start;
  assign start = valid_in && !busy;

  // Division logic
  logic [WIDTH-FRACTION_WIDTH-1:0] divisor;
  logic [WIDTH-1:0] dividend;

  logic [BITS_PER_STAGE-1:0][WIDTH-1:0] dividend_shift;
  logic [BITS_PER_STAGE-1:0][WIDTH-1:0] dividend_subtract;

  logic [BITS_PER_STAGE-1:0] next_quotient;
  logic [FRACTION_WIDTH:0] quotient;

  // Long division algorithm teehee
  always_comb begin
    next_quotient[BITS_PER_STAGE-1] = divisor <= dividend;

    dividend_subtract[0] = (next_quotient[BITS_PER_STAGE-1]) ? dividend - divisor : dividend;
    dividend_shift[0] = dividend_subtract[0] << 1;

    for (int i = 1; i < BITS_PER_STAGE; i++) begin
      next_quotient[BITS_PER_STAGE-1-i] = (divisor <= dividend_shift[i-1]);

      dividend_subtract[i] = (next_quotient[BITS_PER_STAGE-1-i]) ? dividend_shift[i-1] - divisor : dividend_shift[i-1]; // ... and subtract
      dividend_shift[i] = dividend_subtract[i] << 1; // shift
    end
  end

  assign valid_out = cycle_count == NUM_STAGES-1;

  generate
  if (STAGE_OVERFLOW == 0) begin
    always_ff @(posedge clk_in) begin
      quotient_out <= quotient;
    end
  end else begin
    always_ff @(posedge clk_in) begin
      quotient_out <= {quotient, next_quotient[(BITS_PER_STAGE - 1) -: (STAGE_OVERFLOW)]};
    end
  end
  endgenerate

  always_ff @(posedge clk_in) begin
    if (rst_in) begin
      cycle_count <= '0;
      busy <= 0;
      err_out <= 0;

      dividend <= '0;
      divisor <= '0;
      quotient <= '0;
    end else begin
      if (start) begin
        busy <= 1;
        cycle_count <= 1;
        quotient <= '0;

        err_out <= divisor_in == 0;

        divisor <= divisor_in;
        dividend <= dividend_in;
      end else if (busy) begin
        cycle_count <= cycle_count + 1;
        quotient <= {quotient, next_quotient};
        dividend <= dividend_shift[BITS_PER_STAGE-1];

        if (valid_out) begin
          busy <= 0;
          err_out <= 0;
        end
      end
    end
  end
endmodule
`default_nettype wire
