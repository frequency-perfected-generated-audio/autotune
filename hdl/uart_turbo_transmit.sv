`timescale 1ns / 1ps `default_nettype none

typedef enum {
    READY,
    WAIT1,
    SENDING1,
    WAIT2,
    SENDING2
} state_e;

module uart_turbo_transmit #(
    parameter int INPUT_CLOCK_FREQ,
    parameter int BAUD_RATE
) (
    input wire clk_in,
    input wire rst_in,

    input wire [15:0] data_in,
    input wire trigger_in,

    output logic busy_out,
    output logic tx_wire_out

);

    logic uart_trigger;
    logic [7:0] uart_data;
    logic uart_busy;
    uart_transmit #(
        .INPUT_CLOCK_FREQ(INPUT_CLOCK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) uart_tx (
        .clk_in(clk_in),
        .rst_in(rst_in),

        .data_byte_in(uart_data),
        .trigger_in  (uart_trigger),

        .busy_out(uart_busy),
        .tx_wire_out(tx_wire_out)
    );

    logic [7:0] second_byte;
    state_e state;
    always_ff @(posedge clk_in) begin
        if (rst_in) begin
            uart_trigger <= 0;
            state <= READY;
            busy_out <= '0;
        end else begin
            case (state)
                READY: begin
                    if (trigger_in && !busy_out) begin
                        state <= WAIT1;
                        uart_trigger <= '1;
                        uart_data <= data_in[15:8];

                        second_byte <= data_in[7:0];
                        busy_out <= '1;
                    end
                end
                WAIT1:   state <= SENDING1;
                SENDING1: begin
                    if (!uart_busy) begin
                        state <= WAIT2;
                        uart_trigger <= '1;
                        uart_data <= second_byte;
                    end
                end
                WAIT2:   state <= SENDING2;
                SENDING2: begin
                    if (!uart_busy) begin
                        state <= READY;
                        busy_out <= 0;
                    end
                end
                default: ;  // Impossible!
            endcase

            if (uart_trigger) begin
                uart_trigger <= '0;
            end
        end
    end

endmodule
`default_nettype wire
