`default_nettype wire
module top_level (
    input  wire        clk_100mhz,
    input  wire  [3:0] btn,
    output logic       spkl,
    spkr,

    // I2S signals
    input  wire  sdata,
    output logic sclk,
    output logic ws
);

    logic sys_rst;
    assign sys_rst = btn[0];

    logic [15:0] raw_mic_data;
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
        .data_valid_out(raw_mic_data_valid)
    );

    logic [7:0] sample;
    always_ff @(posedge clk_100mhz) begin
        if (raw_mic_data_valid) begin
            sample <= raw_mic_data >> 8;
        end
    end

    logic spk_out;
    pwm audio_generator (
        .clk_in (clk_100mhz),
        .rst_in (sys_rst),
        .dc_in  (sample),
        .sig_out(spk_out)
    );
    assign spkl = spk_out;
    assign spkr = spk_out;

endmodule

`default_nettype none
