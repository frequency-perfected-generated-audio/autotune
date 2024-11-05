`default_nettype none
module fp_div #(
    parameter WIDTH = 32,
    parameter FRACTION_WIDTH = 10,
    parameter NUM_STAGES = 7
) (
    input wire clk_in,
    input wire rst_in,

    input wire [WIDTH-1:0] dividend_in,
    input wire [WIDTH-1:0] divisor_in,
    input wire valid_in,

    output logic [WIDTH-1:0] quotient_out,
    output logic valid_out,
    output logic err_out,
    output logic busy
);
  // FRACTION_WIDTH possible extra fractional digits to check for in fp
  localparam int unsigned DIVIDEND_WIDTH = WIDTH+FRACTION_WIDTH;

  // Stream in first WIDTH digits at a time
  localparam int unsigned DIVISOR_WIDTH = DIVIDEND_WIDTH + WIDTH;

  // Save last stage to register output
  localparam int unsigned NUM_WORKING_STAGES = NUM_STAGES-1;

  // Need DIVIDEND_WIDTH + 1 cycles ordinarily, so perform all stage
  // calculations with that in mind
  localparam int unsigned BITS_PER_STAGE = ((DIVIDEND_WIDTH) / NUM_WORKING_STAGES) + 1; // Jank ceiling
  localparam int unsigned STAGE_OVERFLOW = (DIVIDEND_WIDTH + 1) - (NUM_WORKING_STAGES-1) * BITS_PER_STAGE;

  // control signals
  logic [$clog2(WIDTH+1)-1:0] cycle_count;

  logic start;
  assign start = valid_in && !busy;

  // Division logic
  logic [DIVISOR_WIDTH-1:0] divisor_shift;
  logic [BITS_PER_STAGE-1:0][DIVISOR_WIDTH-1:0] next_divisor_shift;

  logic [DIVIDEND_WIDTH-1:0] dividend_in_progress;
  logic [BITS_PER_STAGE-1:0][DIVIDEND_WIDTH-1:0] next_dividend_in_progress;

  logic [BITS_PER_STAGE-1:0] next_quotient;
  logic [DIVIDEND_WIDTH-1:0] quotient;

  // Long division algorithm teehee
  always_comb begin
    next_divisor_shift[0] = (start) ? {divisor_in, {(DIVIDEND_WIDTH){1'b0}}} : divisor_shift >> 1;
    next_dividend_in_progress[0] = (start) ? {dividend_in, {FRACTION_WIDTH{1'b0}}} : (divisor_shift <= dividend_in_progress) ? dividend_in_progress - divisor_shift : dividend_in_progress;
    next_quotient[BITS_PER_STAGE-1] = (start) ? 0 : (next_divisor_shift[0] <= next_dividend_in_progress[0]);

    for (int i = 1; i < BITS_PER_STAGE; i++) begin
      next_divisor_shift[i] = next_divisor_shift[i-1] >> 1; // Shift ...
      next_dividend_in_progress[i] = (next_divisor_shift[i-1] <= next_dividend_in_progress[i-1]) ? next_dividend_in_progress[i-1] - next_divisor_shift[i-1] : next_dividend_in_progress[i-1]; // ... and subtract

      next_quotient[BITS_PER_STAGE-1-i] = (next_divisor_shift[i] <= next_dividend_in_progress[i]);
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

      dividend_in_progress <= '0;
      divisor_shift <= '0;
      quotient <= '0;
    end else begin
      if (start) begin
        busy <= 1;
        cycle_count <= 1;
        quotient <= {{(DIVIDEND_WIDTH-BITS_PER_STAGE){1'b0}}, next_quotient};

        err_out <= divisor_in == 0;
      end else if (busy) begin
        cycle_count <= cycle_count + 1;
        quotient <= {quotient, next_quotient};

        // Single Cycle Valid
        if (valid_out) begin
          busy <= 0;
          err_out <= 0;
        end
      end

      divisor_shift <= next_divisor_shift[BITS_PER_STAGE-1];
      dividend_in_progress <= next_dividend_in_progress[BITS_PER_STAGE-1];
    end
  end
endmodule
`default_nettype wire
