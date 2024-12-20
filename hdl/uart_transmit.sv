`timescale 1ns / 1ps
`default_nettype none

module uart_transmit #(
    parameter int INPUT_CLOCK_FREQ,
    parameter int BAUD_RATE
) (
    input wire clk_in,
    input wire rst_in,

    input wire [7:0] data_byte_in,
    input wire trigger_in,

    output logic busy_out,
    output logic tx_wire_out

);
  parameter int CYCLES_PER_BAUD = INPUT_CLOCK_FREQ / BAUD_RATE;
  parameter int CYCLES_PER_BAUD_BITS = $clog2(CYCLES_PER_BAUD);

  logic [7:0] data;
  // use one extra bit so we can store 8+2=10, then react to when we see
  // this value is 11
  logic [2+1:0] bits_transmitted;
  logic [CYCLES_PER_BAUD_BITS-1:0] cycle;

  always_ff @(posedge clk_in) begin
    if (rst_in) begin
      bits_transmitted <= 0;
      cycle <= 0;

      tx_wire_out <= 1;
      busy_out <= 0;
    end else if (trigger_in) begin
      bits_transmitted <= 0;
      cycle <= 0;
      data <= data_byte_in;
      busy_out <= 1;
    end else if (busy_out == 1) begin
      if (bits_transmitted == 10) begin
        busy_out <= 0;
        tx_wire_out <= 1;
      end else begin
          if (bits_transmitted == 0) begin
              tx_wire_out <= 0;
          end else if (bits_transmitted == 9) begin
              tx_wire_out <= 1;
          end else begin
              tx_wire_out <= data[bits_transmitted - 1];
          end

        if (cycle == CYCLES_PER_BAUD - 1) begin
          cycle <= 0;
          bits_transmitted <= bits_transmitted + 1;
        end else begin
          cycle <= cycle + 1;
        end
      end
    end else begin
      busy_out <= 0;
      tx_wire_out <= 1;
    end
  end

endmodule

`default_nettype wire
