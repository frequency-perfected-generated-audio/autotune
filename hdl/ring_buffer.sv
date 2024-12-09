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

  always_ff @(posedge clk_in) begin
    if (rst_in) begin
      head <= 0;
      tail <= 0;
    end else begin
      if (shift_trigger) begin
          if (head == ENTRIES - 1) begin
              head <= 0;
          end else begin
              head <= head + 1;
          end
      end

      if (read_trigger) begin
          if (tail == ENTRIES - 1) begin
              tail <= 0;
          end else begin
              tail <= tail + 1;
          end
      end

      data_valid_pipe <= read_trigger;
      data_valid_out <= data_valid_pipe;
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
      .dinb(),
      .web(1'b0),
      .doutb(data_out),

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
