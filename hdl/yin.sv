`default_nettype none
module yin #(
    parameter WIDTH = 16,
    parameter WINDOW_SIZE = 2048,
    parameter DIFFS_PER_BRAM = 512,
    parameter TAUMAX = 2048
) (
    input wire clk_in,
    input wire rst_in,

    input wire [WIDTH-1:0] sample_in,
    input wire valid_in,

    output logic valid_out,
    output logic [$clog2(TAUMAX)-1:0] taumin
);
    localparam int unsigned SAMPLES_PER_BRAM = 2*DIFFS_PER_BRAM;

    localparam int unsigned NUM_BRAM = WINDOW_SIZE / SAMPLES_PER_BRAM;
    localparam int unsigned LOG_BRAM = $clog2(NUM_BRAM);
    localparam int unsigned NUM_BRAM_PORTS = NUM_BRAM*2;
    localparam int unsigned LOG_BRAM_PORTS = LOG_BRAM*2;

    localparam int unsigned TAU_WIDTH = $clog2(TAUMAX);
    localparam int unsigned TAU_PER_BRAM = TAUMAX / NUM_BRAM;

    localparam int unsigned NUM_DIV_CYCLES = 11;
    localparam int unsigned NUM_CUMDIFF_CYCLES = NUM_DIV_CYCLES+5;

    localparam int unsigned DIFF_WIDTH = 42;
    localparam int unsigned FRACTION_WIDTH = 15;
    localparam int unsigned FP_WIDTH = DIFF_WIDTH+FRACTION_WIDTH;

    localparam logic[FRACTION_WIDTH+TAU_WIDTH:0] EARLY_CD = {'0, 1'b0, 15'b000110011001100};

    // COUNTERS/PIPELINE CONTROL
    logic processing_sample;
    logic processing_cd;
    logic [$clog2(WINDOW_SIZE)-1:0] sample;
    logic [WIDTH-1:0] current_sample;

    logic [$clog2(NUM_CUMDIFF_CYCLES)-1:0] cumdiff_cycles;
    logic cycle_toggle;
    logic window_toggle;

    // SAMPLE BRAM CONTROL
    logic [NUM_BRAM-1:0] wen_s;
    logic [$clog2(SAMPLES_PER_BRAM)-1:0] write_addr_s;
    assign write_addr_s = ((sample >> LOG_BRAM_PORTS) << 1) + sample[0];
    logic [5:0][$clog2(SAMPLES_PER_BRAM)-1:0] read_addr_s;

    // DIFF BRAM CONTROL
    logic [NUM_BRAM_PORTS-1:0][TAU_WIDTH-1:0] tau_r;
    logic [NUM_BRAM_PORTS-1:0][TAU_WIDTH-1:0] tau_w;
    logic [NUM_BRAM_PORTS-1:0] wen_d;
    logic [NUM_BRAM_PORTS-1:0][$clog2(TAU_PER_BRAM)-1:0] write_addr_d;
    logic [NUM_BRAM_PORTS-1:0][$clog2(TAU_PER_BRAM)-1:0] read_addr_d;

    // CUMDIFF BRAM CONTROL
    logic [NUM_BRAM_PORTS-1:0][TAU_WIDTH-1:0] tau_cd;
    logic [NUM_BRAM-1:0][TAU_WIDTH-1:0] tau_cd_cmp;
    logic [$clog2(TAU_PER_BRAM)-1:0] read_addr_cd;

    // CUMDIFF OUTPUTS
    logic [NUM_BRAM_PORTS-1:0][DIFF_WIDTH-1:0] cd_diff;
    logic [NUM_BRAM_PORTS-1:0][DIFF_WIDTH-1:0] cd_diff_pipe;

    logic [NUM_BRAM_PORTS-1:0][DIFF_WIDTH-1:0] cd_add;
    logic [NUM_BRAM_PORTS-1:0] cd_div_valid;
    logic [NUM_BRAM_PORTS-1:0] cd_div_err;
    logic [NUM_BRAM_PORTS-1:0][FRACTION_WIDTH:0] cd_div;
    logic [NUM_BRAM_PORTS-1:0][FRACTION_WIDTH+TAU_WIDTH:0] cd_mul_reg;
    logic [NUM_BRAM-1:0][FRACTION_WIDTH+TAU_WIDTH:0] cd_mul;

    // CUMDIFF MIN FINDING CTRL
    logic cmp_cycle_select;
    assign cmp_cycle_select = (cumdiff_cycles == NUM_DIV_CYCLES + 4);
    logic [NUM_BRAM-1:0][TAU_WIDTH-1:0] next_taumin;
    logic [FRACTION_WIDTH+TAU_WIDTH:0] cd_min;
    logic [NUM_BRAM-1:0][FRACTION_WIDTH+TAU_WIDTH:0] next_cd_min;
    logic min_reached;
    logic [NUM_BRAM-1:0] next_min_reached;
    logic [NUM_BRAM-1:0] update;
    logic [NUM_BRAM-1:0] early_out;

    // STAGE OUTPUTS
    logic [NUM_BRAM_PORTS-1:0][WIDTH-1:0] sample_out;
    logic [NUM_BRAM_PORTS-1:0][WIDTH-1:0] subtracted;
    logic [NUM_BRAM_PORTS-1:0][DIFF_WIDTH-1:0] multiplied;
    logic [NUM_BRAM_PORTS-1:0][DIFF_WIDTH-1:0] diff;
    logic [NUM_BRAM_PORTS-1:0][DIFF_WIDTH-1:0] added;

    // BRAM OUTPUTS - alternate to prevent clobbering
    logic [1:0][NUM_BRAM_PORTS-1:0][DIFF_WIDTH-1:0] diff_out;

    logic reset_window;
    assign reset_window = (read_addr_s[5] == SAMPLES_PER_BRAM - 2) && (sample == WINDOW_SIZE - 1);

    always_comb begin
        // DIFF/CUMDIFF BRAM MUXING
        diff = (window_toggle) ? diff_out[1] : diff_out[0];
        cd_diff = (window_toggle) ? diff_out[0] : diff_out[1];

        for (int i = 0; i < NUM_BRAM_PORTS; i++) begin
            // STAGE 3 ADDR CALCULATION AND DIFF BRAM MUXING
            case (sample[LOG_BRAM_PORTS-1:0])
                2'b00: begin
                    tau_w[(4-(i)) % 4] = sample - ((read_addr_s[4] << LOG_BRAM) + i);
                    tau_r[(4-(i)) % 4] = sample - ((read_addr_s[2] << LOG_BRAM) + i);
                end
                2'b01: begin
                    tau_w[(5-(i)) % 4] = sample - ((read_addr_s[4] << LOG_BRAM) + i);
                    tau_r[(5-(i)) % 4] = sample - ((read_addr_s[2] << LOG_BRAM) + i);
                end
                2'b10: begin
                    tau_w[(6-(i)) % 4] = sample - ((read_addr_s[4] << LOG_BRAM) + i);
                    tau_r[(6-(i)) % 4] = sample - ((read_addr_s[2] << LOG_BRAM) + i);
                end
                default: begin
                    tau_w[(3-(i))    ] = sample - ((read_addr_s[4] << LOG_BRAM) + i);
                    tau_r[(3-(i))    ] = sample - ((read_addr_s[2] << LOG_BRAM) + i);
                end
            endcase
        end
        for (int i = 0; i < NUM_BRAM_PORTS; i++) begin
            tau_cd[i] = (read_addr_cd << LOG_BRAM) + i;
        end

        for (int i = 0; i < NUM_BRAM_PORTS; i++) begin
            // STAGE 2 ADDR CALCULATION
            read_addr_d[i] = ((tau_r[i] >> LOG_BRAM_PORTS) << 1) + (tau_r[i] & 1'b1);
        end

        cd_mul = (cmp_cycle_select) ? cd_mul_reg[NUM_BRAM +: NUM_BRAM] : cd_mul_reg[0 +: NUM_BRAM];
        tau_cd_cmp = (cmp_cycle_select) ? tau_cd[NUM_BRAM +: NUM_BRAM] : tau_cd[0 +: NUM_BRAM];

        // MIN FINDING
        update[0] = (cd_mul[0] < cd_min) && !min_reached;
        early_out[0] = cd_min < EARLY_CD;
        next_min_reached[0] = (early_out[0] && !update[0]) || min_reached;

        next_taumin[0] = (update[0]) ? tau_cd_cmp[0] : taumin;
        next_cd_min[0] = (update[0]) ? cd_mul[0] : cd_min;

        for (int i = 1; i < NUM_BRAM; i++) begin
            update[i] = (cd_mul[i] < next_cd_min[i-1]) && !next_min_reached[i-1];
            early_out[i] = next_cd_min[i-1] < EARLY_CD;
            next_min_reached[i] = (early_out[i] && !update[i]) || next_min_reached[i-1];

            next_taumin[i] = (update[i]) ? tau_cd_cmp[i] : next_taumin[i-1];
            next_cd_min[i] = (update[i]) ? cd_mul[i] : next_cd_min[i-1];
        end
    end

    always_ff @(posedge clk_in) begin
        if (rst_in || reset_window) begin
            subtracted <= '0;
            multiplied <= '0;
            added <= '0;

            write_addr_d <= '0;
            wen_d <= '0;

            cd_add <= '0;
            cd_diff_pipe <= '0;

            taumin <= '0;
            cd_min <= {(FRACTION_WIDTH+TAU_WIDTH+1){1'b1}};
            min_reached <= '0;
        end else begin
            for (int i = 0; i < NUM_BRAM_PORTS; i ++) begin
                // STAGE 2: SUB + MUL
                subtracted[i] <= (sample_out[i] < current_sample) ? current_sample - sample_out[i] : sample_out[i] - current_sample;
                multiplied[i] <= subtracted[i]*subtracted[i];

                // STAGE 3 ADD TO DIFF + ADDR CALCULATION
                case (sample[LOG_BRAM_PORTS-1:0])
                    2'b00:
                        added[(4-(i)) % 4] <= diff[(4-(i)) % 4] + multiplied[i];
                    2'b01:
                        added[(5-(i)) % 4] <= diff[(5-(i)) % 4] + multiplied[i];
                    2'b10:
                        added[(6-(i)) % 4] <= diff[(6-(i)) % 4] + multiplied[i];
                    default:
                        added[(3-(i))] <= diff[(3-(i))] + multiplied[i];
                endcase

                write_addr_d[i] <= ((tau_w[i] >> LOG_BRAM_PORTS) << 1) + (tau_w[i] & 1'b1);
                wen_d[i] <= (tau_w[i] <= sample) && (!cycle_toggle) && (read_addr_s[2] != read_addr_s[4]);
            end

            // CUMDIFF PREFIX SUM
            if (cumdiff_cycles == 2) begin
                cd_add[0] <= cd_add[3] + cd_diff[0];
                cd_add[1] <= cd_add[3] + cd_diff[0] + cd_diff[1];
                cd_add[2] <= cd_add[3] + cd_diff[0] + cd_diff[1] + cd_diff[2];
                cd_add[3] <= cd_add[3] + cd_diff[0] + cd_diff[1] + cd_diff[2] + cd_diff[3];

                cd_diff_pipe <= cd_diff;
            end else if (cumdiff_cycles == 2 + NUM_DIV_CYCLES) begin
                for (int i = 0; i < NUM_BRAM_PORTS; i++) begin
                    cd_mul_reg[i] <= (cd_div_err[i]) ? (1 << FRACTION_WIDTH) : (cd_div[i] * tau_cd[i]);
                end
            end else if ((cumdiff_cycles == 3 + NUM_DIV_CYCLES) || (cumdiff_cycles == 4 + NUM_DIV_CYCLES)) begin
                taumin <= next_taumin[NUM_BRAM-1];
                cd_min <= next_cd_min[NUM_BRAM-1];
                min_reached <= next_min_reached[NUM_BRAM-1];
            end else if (valid_out) begin
                cd_add <= '0;
                taumin <= '0;
                cd_min <= {(FRACTION_WIDTH+1){1'b1}};
                min_reached <= '0;
            end
        end
    end

    generate
    genvar i, window, k;
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

            .addrb(read_addr_s[0]+1'b1),
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

        // STAGE 3 WRITEBACK
        for (window = 0; window < 2; window ++) begin
            xilinx_true_dual_port_read_first_1_clock_ram #(
                .RAM_WIDTH(DIFF_WIDTH),
                .RAM_DEPTH(TAU_PER_BRAM),
                .RAM_PERFORMANCE("HIGH_PERFORMANCE")
            ) diff_bram (
                .clka (clk_in),

                .addra((window != window_toggle) ? (read_addr_cd) : wen_d[i*2] ? write_addr_d[i*2] : read_addr_d[i*2]),
                .wea  ((window == window_toggle) && wen_d[i*2]),
                .dina (added[i*2]),
                .douta(diff_out[window][i*2]),
                .rsta((tau_r[i*2] == sample) && (window == window_toggle)),

                .addrb((window != window_toggle) ? (read_addr_cd + 1'b1) : wen_d[i*2+1] ? write_addr_d[i*2+1] : read_addr_d[i*2+1]),
                .web((window == window_toggle) && wen_d[i*2+1]),
                .dinb (added[i*2+1]),
                .doutb(diff_out[window][i*2+1]),
                .rstb((tau_r[i*2+1] == sample) && (window == window_toggle)),

                .ena(1'b1),
                .enb(1'b1),
                .regcea(1'b1),
                .regceb(1'b1)
            );
        end

        // CUMDIFF CALCULATION
        for (k = 0; k < 2; k ++) begin
            fp_div #(
                .WIDTH(FP_WIDTH),
                .FRACTION_WIDTH(FRACTION_WIDTH),
                .NUM_STAGES(NUM_DIV_CYCLES)
            ) u_fp_div (
                .clk_in(clk_in),
                .rst_in(rst_in),

                .dividend_in(cd_diff_pipe[i*2+k]),
                .divisor_in(cd_add[i*2+k]),
                .valid_in(cumdiff_cycles == 3),

                .quotient_out(cd_div[i*2+k]),
                .valid_out(cd_div_valid[i*2+k]),
                .err_out(cd_div_err[i*2+k]),
                .busy()
            );
        end

    end
    endgenerate

    always_ff @(posedge clk_in) begin
        if (rst_in || (read_addr_s[5] == SAMPLES_PER_BRAM-2)) begin
            processing_sample <= 0;
            cycle_toggle <= 0;

            read_addr_s <= '0;
        end
        if (rst_in || reset_window) begin
            sample <= '0;
            current_sample <= '0;
            valid_out <= 0;

            cumdiff_cycles <= '0;
            read_addr_cd <= '0;
            processing_cd <= 0;
        end else if (valid_out) begin
            cumdiff_cycles <= '0;
            read_addr_cd <= '0;
            processing_cd <= 0;
            valid_out <= 0;
        end else if (processing_cd) begin
            cumdiff_cycles <= (cumdiff_cycles == NUM_CUMDIFF_CYCLES - 1) ? 0 : cumdiff_cycles + 1;
            read_addr_cd <= read_addr_cd + ((cumdiff_cycles == NUM_CUMDIFF_CYCLES-1) << 1); // 2 brams
            valid_out <= (read_addr_cd == TAU_PER_BRAM - 2) && (cumdiff_cycles == NUM_CUMDIFF_CYCLES - 1);
        end

        if (rst_in) begin
            window_toggle <= 0;
        end else if (reset_window) begin
            window_toggle <= ~window_toggle;
        end else begin
            if (valid_in) begin
                current_sample <= sample_in;
                processing_sample <= 1;
                if (sample == 0) begin
                    processing_cd <= 1;
                end
            end

            if (read_addr_s[5] == SAMPLES_PER_BRAM - 2) begin
                sample <= sample + 1;
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
