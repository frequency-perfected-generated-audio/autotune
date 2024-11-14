`default_nettype none
module yin #(
    parameter WIDTH = 16,
    parameter WINDOW_SIZE = 2048,
    parameter TAUMAX = 2048
) (
    input wire clk_in,
    input wire rst_in,

    input wire [WIDTH-1:0] sample_in,
    input wire valid_in
);
    localparam int unsigned DIFFS_PER_BRAM = 512;
    localparam int unsigned SAMPLES_PER_BRAM = 2*DIFFS_PER_BRAM;

    localparam int unsigned NUM_BRAM = WINDOW_SIZE / SAMPLES_PER_BRAM;
    localparam int unsigned LOG_BRAM = $clog2(NUM_BRAM);
    localparam int unsigned NUM_BRAM_PORTS = NUM_BRAM*2;
    localparam int unsigned LOG_BRAM_PORTS = LOG_BRAM*2;

    localparam int unsigned TAU_PER_BRAM = TAUMAX / NUM_BRAM;;

    // SAMPLE BRAM CONTROL
    logic [NUM_BRAM-1:0] wen_s;
    logic [$clog2(SAMPLES_PER_BRAM)-1:0] write_addr_s;
    assign write_addr_s = ((sample >> LOG_BRAM_PORTS) << 1) + sample[LOG_BRAM-1:0];
    logic [5:0][$clog2(SAMPLES_PER_BRAM)-1:0] read_addr_s;

    // DIFF BRAM CONTROL
    logic [NUM_BRAM_PORTS-1:0][$clog2(WINDOW_SIZE)-1:0] tau_r;
    logic [NUM_BRAM_PORTS-1:0][$clog2(WINDOW_SIZE)-1:0] tau_w;
    logic [NUM_BRAM_PORTS-1:0] wen_d;
    logic [NUM_BRAM_PORTS-1:0][$clog2(TAU_PER_BRAM)-1:0] write_addr_d;
    logic [NUM_BRAM_PORTS-1:0][$clog2(TAU_PER_BRAM)-1:0] read_addr_d;

    // STAGE OUTPUTS
    logic [NUM_BRAM_PORTS-1:0][WIDTH-1:0] sample_out;
    logic [NUM_BRAM_PORTS-1:0][WIDTH-1:0] subtracted;
    logic [NUM_BRAM_PORTS-1:0][2*WIDTH-1:0] multiplied;
    logic [NUM_BRAM_PORTS-1:0][2*WIDTH-1:0] diff_out;
    logic [NUM_BRAM_PORTS-1:0][2*WIDTH-1:0] added;

    // COUNTERS/PIPELINE CONTROL
    logic processing_sample;
    logic [$clog2(WINDOW_SIZE)-1:0] sample;
    logic [WIDTH-1:0] current_sample;
    logic cycle_toggle;

    logic internal_reset;
    assign internal_reset = (read_addr_s[5] == WINDOW_SIZE - 2) && (sample == WINDOW_SIZE - 1);

    logic reset_diff_bram;
    assign reset_diff_bram = (read_addr_s[2]) == 0 && (sample == 0);

    logic [$clog2(SAMPLES_PER_BRAM)-1:0] tau_0;
    logic [$clog2(SAMPLES_PER_BRAM)-1:0] tau_1;
    logic [$clog2(SAMPLES_PER_BRAM)-1:0] tau_2;
    logic [$clog2(SAMPLES_PER_BRAM)-1:0] tau_3;
    assign tau_0 = tau_r[0];
    assign tau_1 = tau_r[1];
    assign tau_2 = tau_r[2];
    assign tau_3 = tau_r[3];

    logic [$clog2(SAMPLES_PER_BRAM)-1:0] test_d_0;
    logic [$clog2(SAMPLES_PER_BRAM)-1:0] test_d_1;
    logic [$clog2(SAMPLES_PER_BRAM)-1:0] test_d_2;
    logic [$clog2(SAMPLES_PER_BRAM)-1:0] test_d_3;
    assign test_d_0 = read_addr_d[0];
    assign test_d_1 = read_addr_d[1];
    assign test_d_2 = read_addr_d[2];
    assign test_d_3 = read_addr_d[3];

    logic [$clog2(SAMPLES_PER_BRAM)-1:0] test;
    assign test = sample[LOG_BRAM_PORTS-1:0];

    generate
    genvar i;
    for (i = 0; i < NUM_BRAM; i++) begin
        // STAGE 1 READ
        assign wen_s[i] = valid_in && (i == sample[LOG_BRAM_PORTS-1:1]);

        xilinx_true_dual_port_read_first_1_clock_ram #(
            .RAM_WIDTH(WIDTH),
            .RAM_DEPTH(SAMPLES_PER_BRAM),
            .RAM_PERFORMANCE("HIGH_PERFORMANCE")
        ) sample_bram (
            .clka (clk_in),

            .addra((wen_s[i]) ? write_addr_s : read_addr_s[0]),
            .dina (sample_in),
            .wea  (wen_s[i]),
            .douta(sample_out[i*2]),

            .addrb(read_addr_s[0]+1),
            .doutb(sample_out[i*2+1]),

            .dinb(),
            .web(1'b0),
            .ena(1'b1),
            .enb(1'b1),
            .rsta(1'b0),
            .rstb(1'b0),
            .regcea(1'b1),
            .regceb(1'b1)
        );
        always_comb begin
            for (int j = 0; j < 2; j++) begin
                // STAGE 3 ADDR CALCULATION AND DIFF BRAM MUXING
                case (sample[LOG_BRAM_PORTS-1:0])
                    2'b00: begin
                        tau_w[(4-(i*2+j)) % 4] = sample - ((read_addr_s[4] << LOG_BRAM) + i*2+j);
                        tau_r[(4-(i*2+j)) % 4] = sample - ((read_addr_s[2] << LOG_BRAM) + i*2+j);
                    end
                    2'b01: begin
                        tau_w[(5-(i*2+j)) % 4] = sample - ((read_addr_s[4] << LOG_BRAM) + i*2+j);
                        tau_r[(5-(i*2+j)) % 4] = sample - ((read_addr_s[2] << LOG_BRAM) + i*2+j);
                    end
                    2'b10: begin
                        tau_w[(6-(i*2+j)) % 4] = sample - ((read_addr_s[4] << LOG_BRAM) + i*2+j);
                        tau_r[(6-(i*2+j)) % 4] = sample - ((read_addr_s[2] << LOG_BRAM) + i*2+j);
                    end
                    2'b11: begin
                        tau_w[(3-(i*2+j))    ] = sample - ((read_addr_s[4] << LOG_BRAM) + i*2+j);
                        tau_r[(3-(i*2+j))    ] = sample - ((read_addr_s[2] << LOG_BRAM) + i*2+j);
                    end
                endcase
            end

            for (int j = 0; j < 2; j++) begin
                // STAGE 2 ADDR CALCULATION
                read_addr_d[i*2+j] = ((tau_r[i*2+j] >> LOG_BRAM_PORTS) << 1) + (tau_r[i*2+j] & 1'b1);
            end
        end

        always_ff @(posedge clk_in) begin
            if (rst_in) begin
                subtracted <= '0;
                multiplied <= '0;
                added <= '0;

                write_addr_d <= '0;
                wen_d <= '0;
            end else begin
                for (int j = 0; j < 2; j ++) begin
                    // STAGE 2: SUB + MUL
                    subtracted[i*2+j] <= (sample_out[i*2+j] < current_sample) ? current_sample - sample_out[i*2+j] : sample_out[i*2+j] - current_sample;
                    multiplied[i*2+j] <= subtracted[i*2+j]*subtracted[i*2+j];

                    // STAGE 3 ADD TO DIFF + ADDR CALCULATION
                    case (sample[LOG_BRAM_PORTS-1:0])
                        2'b00:
                            added[(4-(i*2+j)) % 4] = diff_out[(4-(i*2+j)) % 4] + multiplied[i*2+j];
                        2'b01:
                            added[(5-(i*2+j)) % 4] = diff_out[(5-(i*2+j)) % 4] + multiplied[i*2+j];
                        2'b10:
                            added[(6-(i*2+j)) % 4] = diff_out[(6-(i*2+j)) % 4] + multiplied[i*2+j];
                        2'b11:
                            added[(3-(i*2+j))] = diff_out[(3-(i*2+j))] + multiplied[i*2+j];
                    endcase

                    write_addr_d[i*2+j] <= ((tau_w[i*2+j] >> LOG_BRAM_PORTS) << 1) + (tau_w[i*2+j] & 1'b1);
                    wen_d[i*2+j] <= (tau_w[i*2+j] <= sample) && (!cycle_toggle) && (read_addr_s[2] != 0);
                end
            end
        end

        // STAGE 3 WRITEBACK
        xilinx_true_dual_port_read_first_1_clock_ram #(
            .RAM_WIDTH(WIDTH*2),
            .RAM_DEPTH(TAU_PER_BRAM),
            .RAM_PERFORMANCE("HIGH_PERFORMANCE")
        ) diff_bram (
            .clka (clk_in),

            .addra(wen_d[i*2] ? write_addr_d[i*2] : read_addr_d[i*2]),
            .wea  (wen_d[i*2]),
            .dina (added[i*2]),
            .douta(diff_out[i*2]),
            .rsta(reset_diff_bram),

            .addrb(wen_d[i*2+1] ? write_addr_d[i*2+1] : read_addr_d[i*2+1]),
            .web(wen_d[i*2+1]),
            .dinb (added[i*2+1]),
            .doutb(diff_out[i*2+1]),
            .rstb(reset_diff_bram),

            .ena(1'b1),
            .enb(1'b1),
            .regcea(1'b1),
            .regceb(1'b1)
        );

    end
    endgenerate

    logic [$clog2(SAMPLES_PER_BRAM)-1:0] top_read_addr;
    assign top_read_addr = read_addr_s[5];

    always_ff @(posedge clk_in) begin
        if (rst_in || internal_reset) begin
            sample <= 0;
            current_sample <= '0;
            processing_sample <= 0;
            cycle_toggle <= 0;

            read_addr_s <= '0;
        end else begin
            if (valid_in) begin
                current_sample <= sample_in;
                processing_sample <= 1;
            end else if (processing_sample && (read_addr_s[5] == SAMPLES_PER_BRAM - 2)) begin
                sample <= sample + 1;
                processing_sample <= 0;
                cycle_toggle <= 0;

                read_addr_s <= '0;
            end else if (processing_sample) begin
                cycle_toggle <= ~cycle_toggle;

                read_addr_s[0] <= (cycle_toggle) ? read_addr_s[0] + 2 : read_addr_s[0];
                for (int i = 1; i < 6; i++) begin
                    read_addr_s[i] <= read_addr_s[i-1];
                end
            end
        end
    end

endmodule
`default_nettype wire
