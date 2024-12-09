`default_nettype none
module ring_buffer #(
    parameter int ENTRIES = 2048,
    parameter int DATA_WIDTH = 32
) (
    input wire clk_in,
    input wire rst_in,

    // Write Inputs
    input wire [DATA_WIDTH-1:0] shift_data,
    input wire shift_trigger,

    // Read Inputs
    input wire read_trigger,

    // Outputs
    output logic [DATA_WIDTH-1:0] data_out,
    output logic data_valid_out
);

  localparam int ADDRSIZE = $clog2(ENTRIES);

  logic [ADDRSIZE-1:0] head;
  logic [ADDRSIZE-1:0] tail;
  logic data_valid_pipe;

  logic [DATA_WIDTH-1:0] line_buffer_out;

  logic cycle_toggle;

  logic [DATA_WIDTH-1:0] crossing_data;
  logic [1:0][DATA_WIDTH-1:0] old_tail_data;
  assign crossing_data = (cycle_toggle) ? old_tail_data[0] : old_tail_data[1];

  logic crossing;
  assign crossing = head == tail;

  logic zero_flag;

  assign data_out = (!crossing) ? line_buffer_out : crossing_data;
  assign zero_flag = data_out == '0 && data_valid_out;

  always_ff @(posedge clk_in) begin
    if (rst_in) begin
      head <= 0;
      tail <= 0;
      cycle_toggle <= 0;

      old_tail_data <= '0;
    end else begin
      if (shift_trigger) begin
          head <= (head == ENTRIES - 1) ? 0 : head + 1;
      end

      if (read_trigger) begin
          cycle_toggle <= ~cycle_toggle;
          if (!crossing) begin
              tail <= (tail == ENTRIES - 1) ? 0 : tail + 1;
              old_tail_data <= {old_tail_data, line_buffer_out};
          end
      end

      data_valid_out <= read_trigger;
    end
  end

  xilinx_true_dual_port_read_first_1_clock_ram #(
      .RAM_WIDTH(DATA_WIDTH),
      .RAM_DEPTH(ENTRIES),
      .RAM_PERFORMANCE("HIGH_PERFORMANCE")
  ) line_buffer_ram (
      // Writing Port
      .addra(head),
      .dina (shift_data),
      .wea  (shift_trigger),
      .douta(),

      // Reading Port
      .addrb(tail),
      .dinb('b0),
      .web(read_trigger && !crossing),
      .doutb(line_buffer_out),

      // Other stuff
      .clka (clk_in),
      .ena(1'b1),
      .enb(1'b1),
      .rsta(1'b0),
      .rstb(1'b0),
      .regcea(1'b1),
      .regceb(1'b1)
  );
endmodule
`default_nettype wire
