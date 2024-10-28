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
    input wire [ADDRSIZE-1:0] read_addr,
    input wire read_trigger,
    // Outputs
    output logic shift_ready_out,
    output logic read_ready_out,
    output logic [DATA_WIDTH-1:0] data_out,
    output logic data_valid_out
);

  localparam int ADDRSIZE = $clog2(ENTRIES);

  logic [ADDRSIZE-1:0] head;
  logic [ADDRSIZE-1:0] actual_read_addr;
  assign actual_read_addr = (read_addr < ENTRIES - head)
                              ? head + read_addr
                              : {1'b0, head} + {1'b0, read_addr} - ENTRIES; // add 0 to avoid overflow
  logic data_valid_pipe;

  always_ff @(posedge clk_in) begin
    if (rst_in) begin
      head <= 0;
      shift_ready_out <= 1;
      read_ready_out <= 1;
    end else begin
      if (shift_trigger) begin
        head <= head + 1;
      end

      data_valid_pipe <= read_trigger;
      data_valid_out <= data_valid_pipe;

      shift_ready_out <= ~shift_trigger;
      read_ready_out <= ~read_trigger;
    end
  end

  xilinx_true_dual_port_read_first_1_clock_ram #(
      .RAM_WIDTH(DATA_WIDTH),
      .RAM_DEPTH(ENTRIES),
      .RAM_PERFORMANCE("HIGH_PERFORMANCE")
  ) line_buffer_ram (
      .clka (clk_in),
      // Writing Port
      .addra(head),
      .dina (shift_data),
      .wea  (shift_trigger),

      // Reading Port
      .addrb(actual_read_addr),  // Port B address bus,
      .doutb(data_out),  // Port B RAM output data,

      // Other stuff
      .douta(),
      .dinb(),
      .web(1'b0),
      .ena(1'b1),
      .enb(1'b1),
      .rsta(1'b0),
      .rstb(1'b0),
      .regcea(1'b1),
      .regceb(1'b1)
  );
endmodule
`default_nettype wire
