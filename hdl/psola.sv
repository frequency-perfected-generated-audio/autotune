`default_nettype none
module psola #(
    parameter int WINDOW_SIZE = 2048
) (
    input wire clk_in,
    input wire rst_in,

    // Actual audio processing
    input wire tau_valid_in,
    input wire [10:0] tau_in,

    output logic [11:0] window_len_out,
    output logic window_len_valid_out,

    // BRAM Handling
    input wire [31:0] signal_val,  // from read_addr 2 cycles ago
    // FRUTI: should there be a valid here?
    input wire [31:0] curr_processed_val, // from write_addr 2 cycles ago, already summed value at write location (which needs to be added to)

    output logic [LOG_WINDOW_SIZE:0] read_addr,
    output logic [LOG_WINDOW_SIZE:0] write_addr,

    output logic [31:0] write_val,  // for current_write_addr
    output logic [LOG_WINDOW_SIZE:0] write_addr_piped,
    output logic valid_write
);

    localparam int LOG_WINDOW_SIZE = $clog2(WINDOW_SIZE);
    logic [1:0] phase;

    /// PHASE 1 LOGIC ////////

    logic [11:0] shifted_tau_in;
    logic [11:0] shifted_tau_in_temp;
    logic [11:0] inv_tau_in;
    logic [11:0] inv_tau_in_temp;

    logic shifted_tau_in_found;
    logic inv_tau_in_found;

    logic div_valid_out;
    logic search_valid_out;

    ////////////////////////////
    /// PHASE 2 LOGIC ////////
    ////////////////////////////

    //// Relevant variables ///////////////

    logic [LOG_WINDOW_SIZE:0] i;
    logic [LOG_WINDOW_SIZE:0] j;
    logic [LOG_WINDOW_SIZE:0] offset;

    logic [LOG_WINDOW_SIZE:0] i_piped;
    logic [LOG_WINDOW_SIZE:0] j_piped;
    logic [LOG_WINDOW_SIZE:0] offset_piped;

    logic [31:0] window_func_val;
    logic [31:0] window_func_val_piped;

    assign read_addr  = i + offset;
    assign write_addr = j + offset;

    logic valid_read;
    assign valid_read = (phase == 2 && offset < 2 * tau_in && i + offset < WINDOW_SIZE && i + tau_in < WINDOW_SIZE);
    logic valid_read_piped;

    //// Pipeline logic ///////////////

    pipeline #(
        .STAGES(2),
        .WIDTH (LOG_WINDOW_SIZE + 1)
    ) pipeline_i (
        .clk (clk_in),
        .rst (rst_in),
        .din (i),
        .dout(i_piped)
    );

    pipeline #(
        .STAGES(2),
        .WIDTH (LOG_WINDOW_SIZE + 1)
    ) pipeline_j (
        .clk (clk_in),
        .rst (rst_in),
        .din (j),
        .dout(j_piped)
    );

    pipeline #(
        .STAGES(2),
        .WIDTH (LOG_WINDOW_SIZE + 1)
    ) pipeline_offset (
        .clk (clk_in),
        .rst (rst_in),
        .din (offset),
        .dout(offset_piped)
    );

    pipeline #(
        .STAGES(2),
        .WIDTH (1)
    ) pipeline_valid_read (
        .clk (clk_in),
        .rst (rst_in),
        .din (valid_read),
        .dout(valid_read_piped)
    );

    pipeline #(
        .STAGES(1),
        .WIDTH (32)
    ) pipeline_window_func (
        .clk (clk_in),
        .rst (rst_in),
        .din (window_func_val),
        .dout(window_func_val_piped)
    );


    ////////////// Division for inv_tau_in ///////////////
    fp_div #(
        .WIDTH(20),
        .FRACTION_WIDTH(10),
        .NUM_STAGES(8)
    ) tau_in_div (
        .clk_in(clk_in),
        .rst_in(rst_in),
        .dividend_in(1),
        .divisor_in(tau_in),
        .valid_in(tau_valid_in),
        .quotient_out(inv_tau_in_temp),
        .valid_out(div_valid_out),
        .err_out(),
        .busy()
    );
    /////////////////////////////////////////////////////

    ////////////// Search for closest semitone ///////////////
    searcher closest_semitone_finder (
        .clk_in(clk_in),
        .rst_in(rst_in),
        .start_search(tau_valid_in),
        .search_val(tau_in),
        .closest_value(shifted_tau_in_temp),
        .closest_value_found(search_valid_out)
    );
    /////////////////////////////////////////////////////


    ///////// Window function calculation ///////////////
    // FRUTI: this might need to be sequential because of the mul
    always_comb begin
        
    end
    /////////////////////////////////////////////////////

    always_ff @(posedge clk_in) begin
        if (rst_in) begin
            window_len_valid_out <= 0;

            i <= 0;
            j <= 0;
            offset <= 0;

            phase <= 0;

            shifted_tau_in <= 0;
            inv_tau_in <= 0;

            shifted_tau_in_found <= 0;
            inv_tau_in_found <= 0;

            window_len_out <= 0;

            write_addr_piped <= 0;
        end else if (tau_valid_in) begin
            window_len_valid_out <= 0;

            i <= 0;
            j <= 0;
            offset <= 0;

            phase <= 1;

            shifted_tau_in <= 0;
            inv_tau_in <= 0;

            shifted_tau_in_found <= 0;
            inv_tau_in_found <= 0;

            window_len_out <= 0;

            write_addr_piped <= 0;
        end else if (phase == 1) begin
            if (div_valid_out) begin
                inv_tau_in_found <= 1;
                inv_tau_in <= inv_tau_in_temp;
            end

            if (search_valid_out) begin
                shifted_tau_in_found <= 1;
                shifted_tau_in <= shifted_tau_in_temp;
            end

            if (inv_tau_in_found && shifted_tau_in_found) begin
                phase <= 2;
            end
        end else if (phase == 2 && i_piped + tau_in < WINDOW_SIZE) begin
            // Logic for setting i, j, offset for reading on next cycle.
            if (i + tau_in < WINDOW_SIZE) begin
                if (offset < 2 * tau_in && i + offset < WINDOW_SIZE) begin
                    offset <= offset + 1;
                end else begin
                    offset <= 0;
                    i <= i + tau_in;
                    j <= j + shifted_tau_in;
                end
            end

            // Logic for using read values from BRAM (with piped i, j, offset to account for cycle delay).
            // From the if statement, we already know that i_piped + tau_in < WINDOW_SIZE.
            if (offset_piped < 2 * tau_in && i_piped + offset_piped < WINDOW_SIZE) begin
                if (j_piped + offset_piped >= window_len_out) begin
                    window_len_out <= j_piped + offset_piped + 1;
                end

                if (i_piped + offset_piped < tau_in && valid_read_piped) begin
                    // FRUTI: are we multiplying by 2**10 because that's the
                    // max window value and we're just leaving the signal
                    // unchanged for the first half of the first pitch period?
                    write_val <= $signed($signed(signal_val) << 10);
                end else if (valid_read_piped) begin
                    write_val <= $signed(curr_processed_val) +
                        $signed(signal_val) * window_func_val_piped;
                end

                write_addr_piped <= j_piped + offset_piped;
                valid_write <= 1;
            end
        end else begin
            if (phase == 2) begin
                window_len_valid_out <= 1;
                // FRUTI
                valid_write <= 0;
            end
            phase <= 0;
        end

        if (offset < tau_in) begin
            window_func_val <= offset * inv_tau_in;
        end else begin
            window_func_val <= (2 << 10) - offset * inv_tau_in;
        end
    end
endmodule
`default_nettype wire
