`default_nettype none

typedef enum {
    WAITING,
    DIVIDING,
    DOING_PSOLA
} phase_e;

typedef enum {
    GET_J1,
    GET_J2,
    GET_I1,
    GET_I2,
    WRITE_J
} psola_phase_e;

module psola_rewrite #(
    parameter int WINDOW_SIZE = 2048
) (
    input logic clk_in,
    input logic rst_in,

    input logic [10:0] tau_in,
    input logic tau_valid_in,

    input logic [15:0] sample_in,
    input logic sample_valid_in,

    output logic [15:0] autotuned_out,
    output logic autotuned_valid_out

);

    phase_e phase;

    logic window_toggle;
    logic [$clog2(WINDOW_SIZE)-1:0] sample_count;

    // DIVIDING
    logic [10:0] tau;
    logic [31:0] tau_inv;
    logic [31:0] tau_inv_raw;
    logic tau_inv_valid;
    logic tau_inv_done;

    fp_div #(
        .WIDTH(32),
        .FRACTION_WIDTH(10),
        .NUM_STAGES(8)
    ) tau_in_div (
        .clk_in(clk_in),
        .rst_in(rst_in),
        .dividend_in(1),
        .divisor_in(tau_in),
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
    logic [31:0] window_coeff;
    logic [$clog2(WINDOW_SIZE):0] i, j, offset;

    always_ff @(posedge clk_in) begin
        if (rst_in) begin
            phase <= WAITING;
            window_toggle <= 0;
            sample_count <= '0;
            tau_inv_done <= 0;
            closest_semitone_done <= 0;
        end else begin
            if (sample_count == WINDOW_SIZE - 1) begin
                sample_count  <= 0;
                window_toggle <= ~window_toggle;
            end else begin
                sample_count <= sample_count - 1;
            end

            case (phase)
                WAITING: begin
                    if (tau_valid_in) begin
                        tau   <= tau_in;
                        phase <= DIVIDING;
                    end
                end
                DIVIDING: begin
                    if (tau_inv_valid) begin
                        tau_inv <= tau_inv_raw;
                        tau_inv_done <= 1;
                    end
                    if (shifted_tau_valid) begin
                        shifted_tau <= shifted_tau_raw;
                        shifted_tau_done <= 1;
                    end
                    if (tau_inv_done && shifted_tau_done) begin
                        phase <= DOING_PSOLA;
                        i <= 0;
                        j <= 0;
                        offset <= 0;
                        window_coeff <= 0;
                    end
                end
                DOING_PSOLA: begin
                    case (psola_phase)
                        GET_J1: begin
                        end
                        GET_J2: begin
                        end
                        GET_I1: begin
                        end
                        GET_I2: begin
                        end
                        WRITE_J: begin
                        end
                        default: ;  // impossible
                    endcase
                end
                default: ;  // impossible
            endcase
        end
    end

    xilinx_true_dual_port_read_first_1_clock_ram #(
        .RAM_WIDTH(32),
        .RAM_DEPTH(2 * WINDOW_SIZE),
        .RAM_PERFORMANCE("HIGH_PERFORMANCE")
    ) psola_bram (
        // A read port, B write port
        .addra(),
        .addrb(),
        .dina(),
        .dinb(),
        .clka(clk_in),
        .wea(0),
        .web(),
        .ena(0),
        .enb(1),
        .rsta(rst_in),
        .rstb(rst_in),
        .regcea(1),
        .regceb(1),
        .douta(),
        .doutb(psola_in_signal_val)
    );

    xilinx_true_dual_port_read_first_1_clock_ram #(
        .RAM_WIDTH(16),
        .RAM_DEPTH(2 * WINDOW_SIZE),
        .RAM_PERFORMANCE("HIGH_PERFORMANCE")
    ) sample_bram (
        // A read port, B write port
        .addra(),
        .addrb(sample_count + (window_toggle ? WINDOW_SIZE : 0)),
        .dina(),
        .dinb(sample_in),
        .clka(clk_in),
        .wea(0),
        .web(sample_valid_in),
        .ena(0),
        .enb(1),
        .rsta(rst_in),
        .rstb(rst_in),
        .regcea(1),
        .regceb(1),
        .douta(),
        .doutb(psola_in_signal_val)
    );

endmodule
`default_nettype none

// xilinx_true_dual_port_read_first_1_clock_ram #(
//     .RAM_WIDTH(32),
//     .RAM_DEPTH(2 * WINDOW_SIZE),
//     .RAM_PERFORMANCE("HIGH_PERFORMANCE")
// ) signal_bram (
//     .addra(window_parity ? addr_in + WINDOW_SIZE : addr_in),
//     .addrb(window_parity ? psola_read_addr : psola_read_addr + WINDOW_SIZE),
//     .dina(sample_in),
//     .dinb(0),
//     .clka(clk_in),
//     .wea(sample_valid_in),
//     .web(0),
//     .ena(1),
//     .enb(1),
//     .rsta(rst_in),
//     .rstb(rst_in),
//     .regcea(1),
//     .regceb(1),
//     .douta(),
//     .doutb(psola_in_signal_val)
// );
