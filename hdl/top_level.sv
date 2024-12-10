`default_nettype wire
module top_level (
    input wire        clk_100mhz,
    input wire [ 3:0] btn,
    input wire [15:0] sw,

    // LED Signals
    output logic [15:0] led,

    // Speaker Signals
    output logic spkl,
    output logic spkr,

    // I2S Signals
    input  wire  sdata,
    output logic sclk,
    output logic ws,

    // UART Signals
    output logic uart_txd,

    // Seven Segment Display Signals
    output logic [3:0] ss0_an,
    output logic [3:0] ss1_an,
    output logic [6:0] ss0_c,
    output logic [6:0] ss1_c,

    // RGB Signals
    output logic [2:0] rgb0,
    output logic [2:0] rgb1
);

    logic sys_rst;
    assign sys_rst = btn[0];

    logic [23:0] raw_mic_data;
    logic        raw_mic_data_valid;
    i2s_receiver i2s_receiver (
        .clk_in(clk_100mhz),
        .rst_in(sys_rst),

        // I2S inputs
        .sdata_in(sdata),

        // I2S Outputs
        .sclk_out(sclk),
        .ws_out  (ws),

        // Data Outputs
        .debug_data_out(raw_mic_data),
        .data_valid_out(raw_mic_data_valid)
    );

    logic [23:0] sample;
    logic        sample_valid;
    always_ff @(posedge clk_100mhz) begin
        if (raw_mic_data_valid) begin
            sample <= raw_mic_data;
        end
        sample_valid <= raw_mic_data_valid;
    end

    logic [15:0] processed_sample;
    logic        processed_sample_valid;
    always_ff @(posedge clk_100mhz) begin
        if (sample_valid) begin
            processed_sample <= sample[23:8];
        end
        processed_sample_valid <= sample_valid;
    end

    // Make LEDs show audio samples
    assign led = processed_sample;

    logic [10:0] raw_taumin;
    logic raw_taumin_valid;

    yin #(
        .WIDTH(16),
        .WINDOW_SIZE(2048),
        .DIFFS_PER_BRAM(512),
        .TAUMAX(2048)
    ) yin (
        .clk_in(clk_100mhz),
        .rst_in(sys_rst),

        .sample_in(processed_sample),
        .valid_in (processed_sample_valid),

        .valid_out(raw_taumin_valid),
        .taumin(raw_taumin)
    );

    logic [10:0] taumin;
    logic taumin_valid;
    always_ff @(posedge clk_100mhz) begin
        if (raw_taumin_valid) begin
            taumin <= raw_taumin;
        end
        taumin_valid <= raw_taumin_valid;
    end

    // Show taumin on seven segment display
    logic [6:0] ss_c;
    seven_segment_controller #(
        .COUNT_PERIOD(100000)
    ) seven_seg (
        .clk_in (clk_100mhz),
        .rst_in (sys_rst),
        .val_in ({21'b0, taumin}),
        .cat_out(ss_c),
        .an_out ({ss0_an, ss1_an})
    );
    assign ss0_c = ss_c;
    assign ss1_c = ss_c;

    bufferizer #(
        .WINDOW_SIZE (20480),
        .MAX_EXTENDED(2200)
    ) buf_dawg (
        .clk_in(clk_100mhz),
        .rst_in(sys_rst),

        .taumin_in(taumin),
        .taumin_valid_in(taumin_valid),

        .sample_in(processed_sample),
        .sample_valid_in(processed_sample_valid),

        .audio_out(raw_audio),
        .audio_valid_out(raw_audio_valid)
    );
    logic [31:0] raw_audio;
    logic raw_audio_valid;
    logic [31:0] audio;
    logic audio_valid;
    always_ff @(posedge clk_100mhz) begin
        if (raw_audio_valid) begin
            audio <= raw_audio;
        end
        audio_valid <= raw_audio_valid;
    end

    uart_turbo_transmit #(
        .INPUT_CLOCK_FREQ(100_000_000),
        .BAUD_RATE(115200)
    ) turbo_uart (
        .clk_in(clk_100mhz),
        .rst_in(sys_rst),

        .data_in({5'b0, taumin}),
        .trigger_in(taumin_valid),

        .busy_out(),
        .tx_wire_out(uart_txd)
    );

    logic spk_out;
    pdm #(
        .NBITS(32)
    ) audio_generator (
        .clk_in(clk_100mhz),
        .d_in  (audio[31:1]),
        .rst_in(sys_rst),
        .d_out (spk_out)
    );
    assign spkl = spk_out;
    assign spkr = spk_out;

endmodule

`default_nettype none
