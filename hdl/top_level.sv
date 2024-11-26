`default_nettype wire
module top_level (
    input wire       clk_100mhz,
    input wire [3:0] btn,
    input wire [15:0] sw,

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

    localparam int unsigned RAW_MIC_DATA_WIDTH = 24;
    localparam int unsigned MIC_DATA_WIDTH = 16;

    logic sys_rst;
    assign sys_rst = btn[0];

    logic [RAW_MIC_DATA_WIDTH-1:0] raw_mic_debug_data;
    logic [RAW_MIC_DATA_WIDTH-1:0] raw_mic_debug_data_pipe;
    logic raw_mic_data_valid;
    logic [1:0] raw_mic_data_valid_pipe;
    i2s_receiver i2s_receiver (
        .clk_in(clk_100mhz),
        .rst_in(sys_rst),

        // I2S inputs
        .sdata_in(sdata),

        // I2S Outputs
        .sclk_out(sclk),
        .ws_out  (ws),

        // Data Outputs
        .debug_data_out(raw_mic_debug_data),
        .data_valid_out(raw_mic_data_valid)
    );

    logic [15:0] sample;
    always_ff @(posedge clk_100mhz) begin
        if (raw_mic_data_valid) begin
            raw_mic_debug_data_pipe <= raw_mic_debug_data;
        end
        case (sw[7:0])
            8'b00000010: sample <= raw_mic_debug_data_pipe[RAW_MIC_DATA_WIDTH-2 -: 16];
            8'b00000100: sample <= raw_mic_debug_data_pipe[RAW_MIC_DATA_WIDTH-3 -: 16];
            8'b00001000: sample <= raw_mic_debug_data_pipe[RAW_MIC_DATA_WIDTH-4 -: 16];
            8'b00010000: sample <= raw_mic_debug_data_pipe[RAW_MIC_DATA_WIDTH-5 -: 16];
            8'b00100000: sample <= raw_mic_debug_data_pipe[RAW_MIC_DATA_WIDTH-6 -: 16];
            8'b01000000: sample <= raw_mic_debug_data_pipe[RAW_MIC_DATA_WIDTH-7 -: 16];
            8'b10000000: sample <= raw_mic_debug_data_pipe[RAW_MIC_DATA_WIDTH-8 -: 16];
            default: sample <= raw_mic_debug_data_pipe[RAW_MIC_DATA_WIDTH-1 -: 16];
        endcase

        raw_mic_data_valid_pipe <= {raw_mic_data_valid_pipe, raw_mic_data_valid};
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
        .WIDTH(MIC_DATA_WIDTH),
        .WINDOW_SIZE(2048),
        .DIFFS_PER_BRAM(512),
        .TAUMAX(2048)
    ) yin (
        .clk_in(clk_100mhz),
        .rst_in(sys_rst),

        .sample_in(sample),
        .valid_in (raw_mic_data_valid_pipe[1]),

        .valid_out(raw_taumin_valid),
        .taumin(raw_taumin)
    );
    //fp_div #(
    //    .WIDTH(42),
    //    .FRACTION_WIDTH(10),
    //    .NUM_STAGES(8)
    //) (
    //    .clk_in(clk_100mhz),
    //    .rst_in(sys_rst),

    //    .dividend_in({16'b0, sample}),
    //    .divisor_in({sample, sample}),
    //    .valid_in(raw_mic_data_valid_pipe[1]),

    //    .quotient_out(raw_taumin),
    //    .valid_out(raw_taumin_valid),
    //    .err_out(),
    //    .busy()
    //);
    logic [10:0] taumin;
    always_ff @(posedge clk_100mhz) begin
        if (raw_taumin_valid) begin
            taumin <= raw_taumin;
        end
    end

    // Show taumin on seven segment display
    logic [6:0] ss_c;
    seven_segment_controller #(
        .COUNT_PERIOD(100000)
    ) seven_seg (
        .clk_in (clk_100mhz),
        .rst_in (sys_rst),
        .val_in ({raw_taumin_valid, 20'b0, taumin}),
        .cat_out(ss_c),
        .an_out ({ss0_an, ss1_an})
    );
    assign ss0_c = ss_c;
    assign ss1_c = ss_c;

    always_ff @(posedge clk_100mhz) begin
        if (raw_taumin_valid) begin
            rgb0 <= 3'b010;
            rgb1 <= 3'b010;
        end
    end

endmodule

`default_nettype none
