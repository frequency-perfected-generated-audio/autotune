`default_nettype none

typedef enum {
    WAITING,
    DIVIDING,
    DOING_PSOLA
} phase_e;

typedef enum {
    READ1,
    READ2,
    VALUE_CALC1,
    VALUE_CALC2,
    WRITE
} psola_phase_e;

module psola_rewrite #(
    parameter int WINDOW_SIZE = 2048
) (
    input wire clk_in,
    input wire rst_in,

    input wire [10:0] tau_in,
    input wire tau_valid_in,

    input wire [15:0] sample_in,
    input wire sample_valid_in,

    output logic [15:0] autotuned_out,
    output logic autotuned_valid_out

);
    localparam int unsigned FRACTION_WIDTH = 11;
    localparam int unsigned MAX_EXTENDED = 2200;

    phase_e phase;

    logic window_toggle;
    logic [$clog2(WINDOW_SIZE)-1:0] sample_count;

    // DIVIDING
    logic [10:0] tau;
    logic [31:0] tau_inv;
    logic [10:0] tau_inv_raw;
    logic tau_inv_valid;
    logic tau_inv_done;

    fp_div #(
        .WIDTH(32),
        .FRACTION_WIDTH(FRACTION_WIDTH),
        .NUM_STAGES(8)
    ) tau_in_div (
        .clk_in(clk_in),
        .rst_in(rst_in),
        .dividend_in(22'h1),
        .divisor_in({11'b0, tau_in}),
        .valid_in(tau_valid_in),
        .quotient_out(tau_inv_raw),
        .valid_out(tau_inv_valid),
        .err_out(),
        .busy()
    );

    logic [11:0] shifted_tau;
    logic [11:0] shifted_tau_raw;
    logic shifted_tau_valid;
    logic shifted_tau_done;
    searcher closest_semitone_finder (
        .clk_in(clk_in),
        .rst_in(rst_in),
        .start_search(tau_valid_in),
        .search_val(tau_in),
        .closest_value(shifted_tau_raw),
        .closest_value_found(shifted_tau_valid)
    );

    // DOING_PSOLA
    psola_phase_e psola_phase;
    logic [FRACTION_WIDTH+1:0] window_coeff; // Always less than 2
    logic [$clog2(WINDOW_SIZE):0] i, j, offset;
    logic [$clog2(WINDOW_SIZE):0] max_offset;

    // BRAM signals
    logic [$clog2(WINDOW_SIZE):0] sample_in_addr;
    assign sample_in_addr = offset + i;
    logic [$clog2(WINDOW_SIZE):0] sample_out_addr;
    assign sample_out_addr = offset + j;
    logic [15:0] data_i;
    logic [31:0] data_i_windowed;
    logic [31:0] data_j_out;
    logic [31:0] data_j_out_delay;
    logic [31:0] data_j_in;

    // OUTPUT VALID
    logic [1:0] sample_valid_pipe;
    assign autotuned_valid_out = sample_valid_pipe[1];

    logic [$clog2(WINDOW_SIZE):0] autotuned_out_addr;

    always_ff @(posedge clk_in) begin
        if (rst_in) begin
            phase <= WAITING;
            window_toggle <= 0;
            sample_count <= '0;
            tau_inv_done <= 0;
            shifted_tau_done <= 0;
            autotuned_out_addr <= '0;
            sample_valid_pipe <= '0;
        end else begin
            // So that we don't change window_toggle/sample_count before
            // we reset the last psola value
            if (sample_valid_pipe[1]) begin
                autotuned_out_addr <= autotuned_out_addr + 1;
                if (sample_count == WINDOW_SIZE - 1) begin
                    sample_count  <= 0;
                    window_toggle <= ~window_toggle;
                end else begin
                    sample_count <= sample_count + 1;
                end
            end
            sample_valid_pipe <= {sample_valid_pipe, sample_valid_in};

            case (phase)
                WAITING: begin
                    if (tau_valid_in) begin
                        tau   <= tau_in;
                        phase <= DIVIDING;
                    end
                end
                DIVIDING: begin
                    if (tau_inv_valid) begin
                        tau_inv <= {21'b0, tau_inv_raw};
                        tau_inv_done <= 1;
                    end
                    if (shifted_tau_valid) begin
                        shifted_tau <= shifted_tau_raw;
                        shifted_tau_done <= 1;
                    end
                    if (tau_inv_done && shifted_tau_done) begin
                        phase <= DOING_PSOLA;
                        psola_phase <= READ1;
                        i <= 0;
                        max_offset <= (tau << 1) < WINDOW_SIZE ? tau << 1 : WINDOW_SIZE;
                        j <= 0;
                        offset <= 0;
                        window_coeff <= 0;
                    end
                end
                DOING_PSOLA: begin
                    case (psola_phase)
                        READ1: psola_phase <= READ2;
                        READ2: psola_phase <= VALUE_CALC1;
                        VALUE_CALC1: begin
                            if (i + offset < tau) begin
                                data_i_windowed <= (data_i << FRACTION_WIDTH);
                            end else begin
                                data_i_windowed <= data_i * window_coeff;
                            end
                            data_j_out_delay <= data_j_out;
                            psola_phase <= VALUE_CALC2;
                        end
                        VALUE_CALC2: begin
                            data_j_in   <= data_i_windowed + data_j_out_delay;
                            psola_phase <= WRITE;
                        end
                        WRITE: begin
                            psola_phase <= READ1;
                            if (offset + 1 < max_offset) begin
                                offset <= offset + 1;
                                if (offset < tau_in) begin
                                    //window_coeff <= window_coeff + (tau_inv << 1);
                                    window_coeff <= (offset+1) * tau_inv;
                                end else begin
                                    //window_coeff <= window_coeff - (tau_inv << 1);
                                    window_coeff <= (2 << FRACTION_WIDTH) - ((offset+1) * tau_inv);
                                end
                                // So that next cycle, i + tau < WINDOW_SIZE
                            end else if (i + (tau << 1) < WINDOW_SIZE) begin
                                i <= i + tau;
                                max_offset <= ((tau << 1) + (i + tau) < WINDOW_SIZE) ? tau << 1 : WINDOW_SIZE - i - tau;
                                j <= j + shifted_tau;
                                offset <= '0;
                                window_coeff <= '0;
                            end else begin
                                phase <= WAITING;
                                tau_inv_done <= 0;
                                shifted_tau_done <= 0;
                                offset <= 0;
                                i <= 0;
                                j <= 0;
                            end
                        end
                    endcase
                end
            endcase
        end
    end

    // PSOLA'ed/'ing signal values
    xilinx_true_dual_port_read_first_1_clock_ram #(
        .RAM_WIDTH(32),
        .RAM_DEPTH(2 * WINDOW_SIZE),
        .RAM_PERFORMANCE("HIGH_PERFORMANCE")
    ) psola_bram (
        // A read port, B write port
        .addra(sample_out_addr + (window_toggle ? WINDOW_SIZE : 0)),
        .dina (data_j_in),
        .wea  (psola_phase == WRITE),
        .douta(data_j_out),

        .addrb(autotuned_out_addr + (window_toggle ? 0 : WINDOW_SIZE)),
        .doutb(autotuned_out),
        .dinb('0),
        .web(sample_valid_pipe[1]),

        .clka(clk_in),
        .ena(1'b1),
        .enb(1'b1),
        .rsta(rst_in),
        .rstb(rst_in),
        .regcea(1'b1),
        .regceb(1'b1)
    );

    xilinx_true_dual_port_read_first_1_clock_ram #(
        .RAM_WIDTH(16),
        .RAM_DEPTH(2 * MAX_EXTENDED),
        .RAM_PERFORMANCE("HIGH_PERFORMANCE")
    ) sample_bram (
        // A read port, B write port
        .addra(sample_in_addr + (window_toggle ? 0 : WINDOW_SIZE)),
        .douta(data_i),

        .addrb(sample_count + (window_toggle ? WINDOW_SIZE : 0)),
        .dinb (sample_in),
        .web  (sample_valid_in),

        .dina(),
        .clka(clk_in),
        .wea(1'b0),
        .ena(1'b1),
        .enb(1'b1),
        .rsta(rst_in),
        .rstb(rst_in),
        .regcea(1'b1),
        .regceb(1'b1),
        .doutb()
    );

endmodule
`default_nettype none
