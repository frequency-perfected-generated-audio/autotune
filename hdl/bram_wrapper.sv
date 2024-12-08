`default_nettype none
module bram_wrapper #(
    parameter int WINDOW_SIZE  = 2048,
    parameter int MAX_EXTENDED = 2200
) (
    input wire clk_in,
    input wire rst_in,

    // YIN output
    input wire tau_valid_in,
    input wire [10:0] tau_in,

    // gets next window of input while running psola on current
    input wire [15:0] sample_in,
    input wire [WINDOW_SIZE_BITS - 1:0] addr_in,
    input wire sample_valid_in,

    output logic [31:0] out_val,
    output logic [MAX_EXTENDED_BITS - 1:0] out_addr_piped,
    output logic valid_out_piped,

    output logic done
);
    localparam int WINDOW_SIZE_BITS = $clog2(WINDOW_SIZE);
    localparam int MAX_EXTENDED_BITS = $clog2(MAX_EXTENDED);

    // determines which portion BRAM to write to, alternates
    // parity 0 indicates using first half for psola, writing to second half; vice versa
    logic window_parity;
    logic psola_parity;

    // State logic
    logic psola_done;
    logic output_done;
    logic read_done;
    logic [1:0] phase;  // 0: psola, 1: output, 2: idle; reading happens in parallel

    // PSOLA module I/O registers
    logic [15:0] psola_in_signal_val;
    logic [31:0] psola_in_curr_processed_val;

    logic [WINDOW_SIZE_BITS - 1:0] psola_read_addr;
    logic [MAX_EXTENDED_BITS - 1:0] psola_write_addr;

    logic [31:0] psola_write_val;
    logic [MAX_EXTENDED_BITS - 1:0] psola_write_addr_piped;
    logic psola_valid_write;

    logic [MAX_EXTENDED_BITS-1:0] psola_output_window_len;

    // BRAM output registers

    logic [MAX_EXTENDED_BITS - 1:0] out_addr;
    logic valid_out;

    // Pipelined output registers

    pipeline #(
        .STAGES(2),
        .WIDTH (1)
    ) valid_out_pipeline (
        .clk (clk_in),
        .rst (rst_in),
        .din (valid_out),
        .dout(valid_out_piped)
    );

    pipeline #(
        .STAGES(2),
        .WIDTH ($clog2(MAX_EXTENDED))
    ) out_addr_pipeline (
        .clk (clk_in),
        .rst (rst_in),
        .din (out_addr),
        .dout(out_addr_piped)
    );


    // BRAM storing PSOLA output values
    // PORT A used for reading current output into PSOLA / out of module, PORT B used for writing psola processed output or clearing
    xilinx_true_dual_port_read_first_1_clock_ram #(
        .RAM_WIDTH(32),
        .RAM_DEPTH(MAX_EXTENDED),
        .RAM_PERFORMANCE("HIGH_PERFORMANCE")
    ) output_bram (
        .addra((phase == 0) ? psola_write_addr : out_addr),
        .dina (0),
        .wea  (phase == 1),
        .douta(out_val),

        .addrb(psola_write_addr_piped),
        .dinb (psola_write_val),
        .web  (psola_valid_write),
        .doutb(),

        .clka(clk_in),
        .ena(1'b1),
        .enb(1'b1),
        .rsta(rst_in),
        .rstb(rst_in),
        .regcea(1'b1),
        .regceb(1'b1)
    );

    assign psola_in_curr_processed_val = out_val;

    psola #(
        .WINDOW_SIZE (WINDOW_SIZE),
        .MAX_EXTENDED(MAX_EXTENDED)
    ) psola_inst (
        .clk_in(clk_in),
        .rst_in(rst_in),

        // YIN interaction
        .tau_valid_in(tau_valid_in),
        .tau_in(tau_in),

        .read_addr(psola_read_addr),

        .signal_val(psola_in_signal_val),
        .curr_processed_val(psola_in_curr_processed_val),
        .write_addr(psola_write_addr),
        .write_val(psola_write_val),
        .write_addr_piped(psola_write_addr_piped),
        .valid_write(psola_valid_write),
        .window_len_out(psola_output_window_len),
        .window_len_valid_out(psola_done)
    );

    // BRAM storing signal values for current and next window
    // PORT A used for getting next window of input, PORT B used to read curr window into PSOLA
    xilinx_true_dual_port_read_first_1_clock_ram #(
        .RAM_WIDTH(16),
        .RAM_DEPTH(2 * WINDOW_SIZE),
        .RAM_PERFORMANCE("HIGH_PERFORMANCE")
    ) signal_bram (
        .addra(window_parity ? addr_in + WINDOW_SIZE : addr_in),
        .dina (sample_in),
        .wea  (sample_valid_in),
        .douta(),

        .addrb(psola_parity ? psola_read_addr + WINDOW_SIZE: psola_read_addr),
        .dinb ('0),
        .web  (1'b0),
        .doutb(psola_in_signal_val),

        .clka(clk_in),
        .ena(1'b1),
        .enb(1'b1),
        .rsta(rst_in),
        .rstb(rst_in),
        .regcea(1'b1),
        .regceb(1'b1)
    );


    always_ff @(posedge clk_in) begin
        if (rst_in) begin
            window_parity <= 0;
            psola_parity <= 0; // TODO: should this be one?

            phase <= 0;
            done <= 0;
            read_done <= 0;
            output_done <= 0;

            valid_out <= 0;
            out_addr <= 0;
        end else if (tau_valid_in) begin
            psola_parity <= ~window_parity;
            phase <= 0;
            read_done <= 0;
            output_done <= 0;

            valid_out <= 0;
            out_addr <= 0;
        end else if (output_done && read_done) begin
            phase <= 0;
            done <= 1;

            valid_out <= 0;
            out_addr <= 0;
        end else if (phase == 0) begin
            if (psola_done) begin
                phase <= 1;
            end
            valid_out <= 0;
        end else if (phase == 1) begin
            if (out_addr_piped == psola_output_window_len - 1) begin
                output_done <= 1;
                valid_out   <= 0;
            end else if (out_addr < psola_output_window_len - 1) begin
                out_addr  <= out_addr + 1;
                valid_out <= 1;
            end else begin
                valid_out <= 0;
            end
        end

        if (addr_in == WINDOW_SIZE - 1 && sample_valid_in) begin
            read_done <= 1;
            window_parity <= ~window_parity;
        end
    end
endmodule
