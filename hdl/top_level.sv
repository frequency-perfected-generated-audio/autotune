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
            processed_sample_number <= 2048 - 1;
        end else if (sample_valid) begin
            processed_sample <= sample[23:8];
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

    assign rgb0  = {2'b0, raw_psola_valid};
    assign rgb1  = {2'b0, raw_psola_done};


    localparam int MAX_EXTENDED = 2200;
    logic [                    31:0] raw_psola;
    logic [$clog2(MAX_EXTENDED)-1:0] raw_psola_addr;
    logic                            raw_psola_valid;

    logic                            raw_psola_done;
    bram_wrapper #(
        .WINDOW_SIZE (2048),
        .MAX_EXTENDED(MAX_EXTENDED)
    ) psola_gen (
        .clk_in(clk_100mhz),
        .rst_in(sys_rst),

        // YIN output
        .tau_in(taumin),
        .tau_valid_in(taumin_valid),

        // gets next window of input while running psola on current
        .sample_in(processed_sample),
        .addr_in(processed_sample_number),
        .sample_valid_in(processed_sample_valid),

        .out_val(raw_psola),
        .out_addr_piped(raw_psola_addr),
        .valid_out_piped(raw_psola_valid),

        .done(raw_psola_done)
    );

    // xilinx_true_dual_port_read_first_1_clock_ram #(
    //     .RAM_WIDTH(32),
    //     .RAM_DEPTH(MAX_EXTENDED * 2),
    //     .RAM_PERFORMANCE("HIGH_PERFORMANCE")
    // ) output_bram (
    //     // A write port, B read port
    //     // might need a -1 here, psola seems to start its address at 1
    //     .addra(raw_psola_addr + (psola_parity ? MAX_EXTENDED : 0)),
    //     .dina (raw_psola),
    //     .wea  (raw_psola_valid),
    //     .douta(),
    //
    //     .addrb(psola_output_addr + (psola_parity ? 0 : MAX_EXTENDED)),
    //     .dinb (),
    //     .web  (1'b0),
    //     .doutb(psola_spk_input),
    //
    //     .clka(clk_in),
    //     .ena(1'b1),
    //     .enb(1'b1),
    //     .rsta(rst_in),
    //     .rstb(rst_in),
    //     .regcea(1'b1),
    //     .regceb(1'b1)
    // );
    //
    // logic psola_parity;
    // logic [31:0] psola_spk_input;
    // logic [$clog2(MAX_EXTENDED)-1:0] psola_output_addr;
    // logic [$clog2(2304)-1:0] psola_hold_count;
    // always_ff @(posedge clk_100mhz) begin
    //     if (sys_rst) begin
    //         psola_parity <= 0;
    //         psola_output_addr <= '0;
    //         psola_hold_count <= '0;
    //     end else begin
    //         // Switch on negedge of psola_valid, aka when samples are done being written
    //         if (raw_psola_done) begin
    //             psola_parity <= ~psola_parity;
    //             psola_hold_count <= '0;
    //             psola_output_addr <= '0;
    //         end else begin
    //             if (psola_hold_count == 2304 - 1) begin
    //                 psola_hold_count  <= 0;
    //                 psola_output_addr <= psola_output_addr + 1;
    //             end else begin
    //                 psola_hold_count <= psola_hold_count + 1;
    //             end
    //         end
    //     end
    // end
    //
    // uart_turbo_transmit #(
    //     .INPUT_CLOCK_FREQ(100_000_000),
    //     .BAUD_RATE(961600)
    // ) turbo_uart (
    //     .clk_in(clk_100mhz),
    //     .rst_in(sys_rst),
    //
    //     .data_in(psola_spk_input[25:10]),
    //     .trigger_in(processed_sample_valid),
    //
    //     .busy_out(),
    //     .tx_wire_out(uart_txd)
    //
    // );
    //
    // logic spk_out;
    // pdm #(
    //     .NBITS(16)
    // ) audio_generator (
    //     .clk_in(clk_100mhz),
    //     .d_in  (psola_spk_input[25:10]),
    //     .rst_in(sys_rst),
    //     .d_out (spk_out)
    // );
    // assign spkl = spk_out;
    // assign spkr = spk_out;


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
    always_ff @(posedge clk_100mhz) begin
        if (raw_audio_valid) begin
            audio <= raw_audio;
        end
    end

    logic spk_out;
    pdm #(
        .NBITS(32)
    ) audio_generator (
        .clk_in(clk_100mhz),
        .d_in  (audio),
        .rst_in(sys_rst),
        .d_out (spk_out)
    );
    assign spkl = spk_out;
    assign spkr = spk_out;

endmodule

`default_nettype none
