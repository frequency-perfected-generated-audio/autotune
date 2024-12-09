`default_nettype none
module bufferizer #(
    parameter int WINDOW_SIZE = 2048,
    parameter int MAX_EXTENDED = 2200,
    parameter int SAMP_PLAY_DURATION = 2304
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
        .sample_in(burst_sample),
        .addr_in(burst_addr_piped),
        .sample_valid_in(burst_valid),

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

    typedef enum {
        LOADING_BUFFER,
        PLAYING
    } state_e;

    state_e state;
    logic [12:0] playing_hold;
    logic read_trigger;
    always_ff @(posedge clk_in) begin
        if (rst_in) begin
            sample_num <= 2048 - 1;  // so that on the first sample we go into 0
            state <= LOADING_BUFFER;
            playing_hold <= '0;
        end else begin
            if (sample_valid_in) begin
                sample <= sample_in;
                if (sample_num == WINDOW_SIZE - 1) begin
                    sample_num <= 0;
                end else begin
                    sample_num <= sample_num + 1;
                end
            end
            sample_valid <= sample_valid_in;

            if (taumin_valid_in) begin
                taumin <= taumin_in;
            end
            taumin_valid <= taumin_valid_in;

            case (state)
                LOADING_BUFFER: begin
                    if (raw_psola_done) begin
                        state <= PLAYING;
                    end
                end
                PLAYING: begin
                    if (playing_hold == SAMP_PLAY_DURATION - 1) begin
                        read_trigger <= 1;
                        playing_hold <= 0;
                    end else begin
                        read_trigger <= 0;
                        playing_hold <= playing_hold + 1;
                    end
                end
                default: ;  // Impossible!
            endcase
        end
    end

    localparam int BURST_PERIOD = 5;
    logic                            burst_active;
    logic                            burst_active_piped;
    logic                            burst_trigger;
    logic [ $clog2(WINDOW_SIZE)-1:0] burst_addr;
    logic [ $clog2(WINDOW_SIZE)-1:0] burst_addr_piped;
    logic [$clog2(BURST_PERIOD)-1:0] burst_hold;

    logic [                    31:0] burst_sample;
    logic                            burst_valid;
    always_ff @(posedge clk_in) begin
        if (rst_in) begin
            burst_active  <= 0;
            burst_addr   <= 0;
            burst_hold    <= 0;
        end else begin
            if (taumin_valid) begin
                burst_active <= 1;
            end else if (burst_active) begin
                if (burst_hold == BURST_PERIOD - 1) begin
                    burst_hold <= 0;

                    if (burst_addr == WINDOW_SIZE - 1) begin
                        // terminate burst
                        burst_active <= 0;
                        burst_addr <= 0;
                        burst_hold <= 0;
                    end else begin
                        burst_addr <= burst_addr + 1;
                    end
                end else begin
                    burst_hold <= burst_hold + 1;
                end
            end
        end
    end
    assign burst_trigger = burst_hold == BURST_PERIOD - 1;

    pipeline #(
        .STAGES(2),
        .WIDTH ($clog2(WINDOW_SIZE))
    ) burst_addr_pipe (
        .clk (clk_in),
        .rst (rst_in),
        .din (burst_addr),
        .dout(burst_addr_piped)
    );

    ring_buffer #(
        .ENTRIES(2 * WINDOW_SIZE),
        .DATA_WIDTH(32)
    ) input_buf (
        .clk_in(clk_in),
        .rst_in(rst_in),
        // Write Inputs
        .shift_data(sample_in),
        .shift_trigger(sample_valid_in),
        // Read Inputs
        .read_trigger(burst_trigger),
        // Outputs
        .data_out(burst_sample),
        .data_valid_out(burst_valid)
    );

    ring_buffer #(
        .ENTRIES(2 * MAX_EXTENDED),
        .DATA_WIDTH(32)
    ) output_buf (
        .clk_in(clk_in),
        .rst_in(rst_in),
        // Write Inputs
        .shift_data(raw_psola),
        .shift_trigger(raw_psola_valid),
        // Read Inputs
        .read_trigger(read_trigger),
        // Outputs
        .data_out(audio_out),
        .data_valid_out(audio_valid_out)
    );

endmodule
`default_nettype wire
