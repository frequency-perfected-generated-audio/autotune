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

    // input logic signed [31:0] dummy_sample,
    // input logic [9:0] dummy_addr,
    //
    // input logic [10:0] output_addr,
    //
    // output logic signed [31:0] out_sample
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
    logic [10:0] processed_sample_number;
    always_ff @(posedge clk_100mhz) begin
        if (sys_rst) begin
            processed_sample_number <= 0;
        end else if (sample_valid) begin
            processed_sample <= sample[23:8];
            // TODO: this might be an off by one
            if (processed_sample_number == 2048 - 1) begin
                processed_sample_number <= 0;
            end else begin
                processed_sample_number <= processed_sample_number + 1;
            end
        end
        processed_sample_valid <= sample_valid;
    end

    // Make LEDs show audio samples
    assign led = processed_sample;

    logic [10:0] raw_taumin;
    logic raw_taumin_valid;


    uart_transmit #(
        .INPUT_CLOCK_FREQ(100_000_000),
        .BAUD_RATE(460800)
    ) uart_tx (
        .clk_in(clk_100mhz),
        .rst_in(sys_rst),

        .data_byte_in(raw_taumin[10:3]),
        .trigger_in  (raw_taumin_valid),

        .busy_out(),
        .tx_wire_out(uart_txd)

    );

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

    assign rgb0  = '0;
    assign rgb1  = '0;

    logic [15:0] psola;
    logic [15:0] raw_psola;
    logic        psola_valid;
    logic        raw_psola_valid;

    psola_rewrite #(
        .WINDOW_SIZE(2048)
    ) psola_gen (
        .clk_in(clk_100mhz),
        .rst_in(sys_rst),

        .tau_in(taumin),
        .tau_valid_in(taumin_valid),

        .sample_in(processed_sample),
        .sample_valid_in(processed_sample_valid),

        .autotuned_out(raw_psola),
        .autotuned_valid_out(raw_psola_valid)
    );

    always_ff @(posedge clk_100mhz) begin
        if (raw_psola_valid) begin
            psola <= raw_psola;
        end
        psola_valid <= raw_psola_valid;
    end

    logic spk_out;
    pdm #(
        .NBITS(16)
    ) audio_generator (
        .clk_in(clk_100mhz),
        .d_in  (psola),
        .rst_in(sys_rst),
        .d_out (spk_out)
    );
    assign spkl = spk_out;
    assign spkr = spk_out;

endmodule

`default_nettype none
