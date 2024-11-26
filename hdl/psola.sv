module psola #(parameter WINDOW_SIZE = 2048) (
    input logic clk_in,
    input logic new_signal,
    input logic [1:0][WINDOW_SIZE-1:0][31:0] signal,
    input logic [11:0] period,
    output logic [WINDOW_SIZE-1:0] out,
    output logic done,
);

localparam int LOG_WINDOW_SIZE = $clog2(WINDOW_SIZE);

logic first_window;

logic [LOG_WINDOW_SIZE-1:0] i;
logic [LOG_WINDOW_SIZE-1:0] j;
logic [LOG_WINDOW_SIZE-1:0] offset;

logic [11:0] shifted_period;
logic [11:0] inv_period;

logic shifted_period_found;
logic inv_period_found;

logic div_valid_out;
logic search_valid_out;

logic [31:0] window_func_val;
logic phase;


fp_div #(
    .WIDTH(12),
    .FRACTION_WIDTH(10),
    .NUM_STAGES(8)
) period_div (
    .clk_in(clk_in),
    .rst_in(new_signal),
    .dividend_in(1),
    .divisor_in(period),
    .valid_in(new_signal),
    .quotient_out(inv_period),
    .valid_out(div_valid_out),
    .err_out(),
    .busy()
);

searcher closest_semitone_finder (
    .clk_in(clk_in),
    .rst_in(new_signal),
    .period(period),
    .closest_period(shifted_period),
    .valid_out(search_valid_out),
    .err_out(),
    .busy()
)

always_comb begin
    if (offset < period) begin
        window_func_val = offset * inv_period; 
    end else begin
        window_func_val = (2 * period - offset) * inv_period;
    end
end

always_ff @(posedge clk_in) begin

    if (rst_in) begin    

        first_window <= 0;

        i <= 0;
        j <= 0;
        offset <= 0;

        phase <= 0;

        shifted_period <= 0;
        inv_period <= 0;

        shifted_period_found <= 0;
        inv_period_found <= 0;

    
    end else if (new_signal) begin

        i <= 0;
        j <= 0;
        offset <= 0;

        phase <= 0;

        shifted_period <= 0;
        inv_period <= 0;

        shifted_period_found <= 0;
        inv_period_found <= 0;

    end else if (phase == 0) begin

        if (div_valid_out) begin
            inv_period_found <= 1;
        end

        if (search_valid_out) begin
            shifted_period_found <= 1;
        end

        if (inv_period_found && shifted_period_found) begin
            phase <= 1;
        end
    
    end else if (i <= WINDOW_SIZE - period) begin
        
        if (offset < 2 * period) begin

            if (i + offset >= WINDOW_SIZE) begin
                out[j + offset] <= signal[~first_window][i + offset - WINDOW_SIZE];
            end else begin
                out[j + offset] <= signal[first_window][i + offset];
            end

            offset <= offset + 1;

        end else begin

            offset <= 0;
            i <= i + period;
            j <= j + shifted_period;

        end

    end else begin

        done <= 1;
        first_window <= ~first_window;

    end

end



endmodule