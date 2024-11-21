`default_nettype wire
module top_level (
    input  wire        clk_100mhz,
    input  wire  [3:0] btn,
    output logic       spkl,
    spkr,

    // I2S signals
    input  wire  sdata,
    output logic sclk,
    output logic ws,

    // UART Signals
    output logic uart_txd
);

    logic sys_rst;
    assign sys_rst = btn[0];

    logic [15:0] raw_mic_data;
    logic [23:0] raw_mic_debug_data;
    logic raw_mic_data_valid;
    i2s_receiver i2s_receiver (
        .clk_in(clk_100mhz),
        .rst_in(sys_rst),

        // I2S inputs
        .sdata_in(sdata),

        // I2S Outputs
        .sclk_out(sclk),
        .ws_out  (ws),

        // Data Outputs
        .data_out(raw_mic_data),
        .debug_data_out(raw_mic_debug_data),
        .data_valid_out(raw_mic_data_valid)
    );

    logic [15:0] sample;
    always_ff @(posedge clk_100mhz) begin
        if (raw_mic_data_valid) begin
            sample <= raw_mic_data;
        end
    end

    logic spk_out;

    pdm #(
        .NBITS(16)
    ) audio_generator (
        .clk_in(clk_100mhz),
        .d_in  (sample),
        .rst_in(sys_rst),
        .d_out (spk_out)
    );
    assign spkl = spk_out;
    assign spkr = spk_out;


    uart_transmit #(
        .INPUT_CLOCK_FREQ(100_000_000),
        .BAUD_RATE(460800)
    ) uart_tx (
        .clk_in(clk_100mhz),
        .rst_in(sys_rst),

        .data_byte_in(raw_mic_debug_data[23:16]),
        .trigger_in  (raw_mic_data_valid),

        .busy_out(),
        .tx_wire_out(uart_txd)

    );

endmodule

`default_nettype none
