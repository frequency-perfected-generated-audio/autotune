`default_nettype none
module psola #(
    parameter WINDOW_SIZE = 2048

    input logic clk_in,
    input logic rst_in,
    input logic new_signal,
    input logic [11:0] period,

    input logic [31:0] signal_val,  // from read_addr 2 cycles ago
    input logic [31:0] curr_processed_val, // from write_addr 2 cycles ago, already summed value at write location (which needs to be added to)

    output logic [LOG_WINDOW_SIZE:0] read_addr,
    output logic [LOG_WINDOW_SIZE:0] write_addr,

    output logic [31:0] write_val,  // for current_write_addr
    output logic [LOG_WINDOW_SIZE:0] write_addr_piped,
    output logic valid_write,

    output logic [11:0] output_window_len,
    output logic done
);

    localparam int LOG_WINDOW_SIZE = $clog2(WINDOW_SIZE);
    logic [1:0] phase;

    /// PHASE 1 LOGIC ////////

    logic [11:0] shifted_period;
    logic [11:0] shifted_period_temp;
    logic [11:0] inv_period;
    logic [11:0] inv_period_temp;

    logic shifted_period_found;
    logic inv_period_found;

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

    assign read_addr  = i + offset;
    assign write_addr = j + offset;

    logic valid_read;
    assign valid_read = (phase == 2 && offset < 2 * period && i + offset < WINDOW_SIZE && i + period < WINDOW_SIZE);
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


    /////////////////////////////////


    ////////////// Division for inv_period ///////////////
    fp_div #(
        .WIDTH(20),
        .FRACTION_WIDTH(10),
        .NUM_STAGES(8)
    ) period_div (
        .clk_in(clk_in),
        .rst_in(rst_in),
        .dividend_in(1),
        .divisor_in(period),
        .valid_in(new_signal),
        .quotient_out(inv_period_temp),
        .valid_out(div_valid_out),
        .err_out(),
        .busy()
    );
    /////////////////////////////////////////////////////

    ////////////// Search for closest semitone ///////////////
    searcher closest_semitone_finder (
        .clk_in(clk_in),
        .rst_in(rst_in),
        .start_search(new_signal),
        .search_val(period),
        .closest_value(shifted_period_temp),
        .closest_value_found(search_valid_out)
    );
    /////////////////////////////////////////////////////


    ///////// Window function calculation ///////////////
    always_comb begin
        if (offset < period) begin
            window_func_val = offset_piped * inv_period;
        end else begin
            window_func_val = (2 << 10) - offset_piped * inv_period;
        end
    end
    /////////////////////////////////////////////////////

    always_ff @(posedge clk_in) begin
        if (rst_in) begin
            done <= 0;

            i <= 0;
            j <= 0;
            offset <= 0;

            phase <= 0;

            shifted_period <= 0;
            inv_period <= 0;

            shifted_period_found <= 0;
            inv_period_found <= 0;

            output_window_len <= 0;

            write_addr_piped <= 0;
        end else if (new_signal) begin
            done <= 0;

            i <= 0;
            j <= 0;
            offset <= 0;

            phase <= 1;

            shifted_period <= 0;
            inv_period <= 0;

            shifted_period_found <= 0;
            inv_period_found <= 0;

            output_window_len <= 0;

            write_addr_piped <= 0;
        end else if (phase == 1) begin
            if (div_valid_out) begin
                inv_period_found <= 1;
                inv_period <= inv_period_temp;
            end

            if (search_valid_out) begin
                shifted_period_found <= 1;
                shifted_period <= shifted_period_temp;
                // shifted_period <= period;
            end

            if (inv_period_found && shifted_period_found) begin
                phase <= 2;
            end
        end else if (phase == 2 && i_piped + period < WINDOW_SIZE) begin
            // Logic for setting i, j, offset for reading on next cycle.
            if (i + period < WINDOW_SIZE) begin
                if (offset < 2 * period && i + offset < WINDOW_SIZE) begin
                    offset <= offset + 1;
                end else begin
                    offset <= 0;
                    i <= i + period;
                    j <= j + shifted_period;
                end
            end

            // Logic for using read values from BRAM (with piped i, j, offset to account for cycle delay).
            // From the if statement, we already know that i_piped + period < WINDOW_SIZE.
            if (offset_piped < 2 * period && i_piped + offset_piped < WINDOW_SIZE) begin
                if (j_piped + offset_piped >= output_window_len) begin
                    output_window_len <= j_piped + offset_piped + 1;
                end

                if (i_piped + offset_piped < period && valid_read) begin
                    write_val <= $signed($signed(signal_val) << 10);
                end else if (valid_read) begin
                    write_val <= $signed(curr_processed_val) +
                        $signed(signal_val) * window_func_val;
                end

                write_addr_piped <= j_piped + offset_piped;
                valid_write <= 1;
            end
        end else begin
            if (phase == 2) begin
                done <= 1;
            end
            phase <= 0;
        end
    end
endmodule
`default_nettype wire
