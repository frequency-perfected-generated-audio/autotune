`default_nettype none
module signal_replayer #(
    parameter string INIT_FILE,
    parameter int SAMPLES = 130_000,  // A little under 3 seconds of audio
    parameter int PERIOD = 2304  // 64 * 36
) (
    input wire clk_in,
    input wire rst_in,

    // Outputs
    output logic [15:0] signal,
    output logic signal_valid_out
);
    logic [$clog2(SAMPLES)-1:0] sample;
    logic [$clog2(PERIOD)-1:0] counter;
    logic done;

    always_ff @(posedge clk_in) begin
        if (rst_in) begin
            sample <= '0;
            counter <= '0;
            done <= 0;
        end else if (~done) begin
            if (counter == PERIOD - 1) begin
                counter <= '0;
                if (sample == SAMPLES - 1) begin
                    done <= 1;
                end else begin
                    sample <= sample + 1;
                end
            end else begin
                counter <= counter + 1;
            end

            if (counter == 1) begin
                signal_valid_out <= 1;
            end else begin
                signal_valid_out <= '0;
            end
        end
    end

    xilinx_true_dual_port_read_first_1_clock_ram #(
        .RAM_WIDTH(16),
        .RAM_DEPTH(SAMPLES),
        .RAM_PERFORMANCE("HIGH_PERFORMANCE"),
        .INIT_FILE(INIT_FILE)
    ) sample_bram (
        .clka(clk_in),

        .addra(sample),
        .dina (),
        .douta(signal),

        .addrb(),
        .dinb (),
        .doutb(),

        .wea(1'b0),
        .web(1'b0),
        .ena(1'b1),  // only enable a
        .enb(1'b0),
        .rsta(1'b0),
        .rstb(1'b0),
        .regcea(1'b1),  // only enable a
        .regceb(1'b0)
    );


endmodule

`default_nettype wire
