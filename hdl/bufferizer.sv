`default_nettype none
module bufferizer #(
    parameter int WINDOW_SIZE  = 2048,
    parameter int MAX_EXTENDED = 2200
) (
    input wire clk_in,
    input wire rst_in,

    input wire [10:0] taumin_in,
    input wire taumin_valid_in,

    input wire [15:0] sample_in,
    input wire sample_valid_in,

    output logic [31:0] audio_out,
    output logic audio_valid_out
);
    bram_wrapper #(
        .WINDOW_SIZE (2048),
        .MAX_EXTENDED(MAX_EXTENDED)
    ) psola_gen (
        .clk_in(clk_in),
        .rst_in(rst_in),

        // YIN output
        .tau_in(taumin),
        .tau_valid_in(taumin_valid),

        // gets next window of input while running psola on current
        .sample_in(sample),
        .addr_in(sample_num),
        .sample_valid_in(sample_valid),

        .out_val(raw_psola),
        .out_addr_piped(raw_psola_addr),
        .valid_out_piped(raw_psola_valid),

        .done(raw_psola_done)
    );

    logic [31:0] raw_psola;
    logic [11:0] raw_psola_addr;
    logic raw_psola_valid;
    logic raw_psola_done;

    logic [$clog2(MAX_EXTENDED)-1:0] sample_num;
    logic [15:0] sample;
    logic sample_valid;

    logic [10:0] taumin;
    logic [10:0] taumin_valid;

    logic hi_side_playing;
    assign audio_valid_out = playing_hold == 2;

    logic [12:0] playing_addr;
    logic [12:0] playing_hold;

    always_ff @(posedge clk_in) begin
        if (rst_in) begin
            sample_num <= 2048 - 1;  // so that on the first sample we go into 0
            playing_addr <= 0;
            playing_hold <= 0;
            hi_side_playing <= 0;
        end else begin
            if (sample_valid_in) begin
                if (sample_num == 2048 - 1) begin
                    sample_num <= 0;
                end else begin
                    sample_num <= sample_num + 1;
                end
                sample <= sample_in;
            end
            sample_valid <= sample_valid_in;

            if (taumin_valid_in) begin
                taumin <= taumin_in;
            end
            taumin_valid <= taumin_valid_in;

            if (raw_psola_done) begin
                hi_side_playing <= ~hi_side_playing;
                playing_addr <= '0;
                playing_hold <= '0;
            end else if (playing_hold == 2304 - 1) begin
                playing_addr <= playing_addr + 1;
                playing_hold <= 0;
            end else begin
                playing_hold <= playing_hold + 1;
            end

        end
    end
    logic [31:0] bram_out;
    xilinx_true_dual_port_read_first_1_clock_ram #(
        .RAM_WIDTH(32),
        .RAM_DEPTH(MAX_EXTENDED * 2),
        .RAM_PERFORMANCE("HIGH_PERFORMANCE")
    ) output_bram (
        // A write port, B read port
        // might need a -1 here, psola seems to start its address at 1
        .addra(raw_psola_addr + (hi_side_playing ? 0 : MAX_EXTENDED)),
        .dina (raw_psola),
        .wea  (raw_psola_valid),
        .douta(),

        .addrb(playing_addr + (hi_side_playing ? MAX_EXTENDED : 0)),
        .dinb (),
        .web  (1'b0),
        .doutb(audio_out),

        .clka(clk_in),
        .ena(1'b1),
        .enb(1'b1),
        .rsta(rst_in),
        .rstb(rst_in),
        .regcea(1'b1),
        .regceb(1'b1)
    );
    // assign audio_out = hi_side_playing ? bram_out : '0;

endmodule
`default_nettype wire
