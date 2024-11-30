module psola #(parameter WINDOW_SIZE = 2048) (
    input logic clk_in,
    input logic rst_in,
    input logic new_signal,
    input logic signed [31:0] signal [WINDOW_SIZE-1:0],
    input logic [11:0] period,
    output logic signed [31:0] out [2*WINDOW_SIZE-1:0],
    output logic [11:0] output_window_len,
    output logic done
);

localparam int LOG_WINDOW_SIZE = $clog2(WINDOW_SIZE);

logic [LOG_WINDOW_SIZE-1:0] i;
logic [LOG_WINDOW_SIZE-1:0] j;
logic [LOG_WINDOW_SIZE-1:0] offset;

logic [11:0] shifted_period;
logic [11:0] shifted_period_temp;
logic [11:0] inv_period;
logic [11:0] inv_period_temp;

logic shifted_period_found;
logic inv_period_found;

logic div_valid_out;
logic search_valid_out;

logic [31:0] window_func_val;
logic [1:0] phase;


fp_div #(
    .WIDTH(12),
    .FRACTION_WIDTH(12),
    .NUM_STAGES(8)
) period_div (
    .clk_in(clk_in),
    .rst_in(new_signal),
    .dividend_in(1),
    .divisor_in(period),
    .valid_in(new_signal),
    .quotient_out(inv_period_temp),
    .valid_out(div_valid_out),
    .err_out(),
    .busy()
);


searcher #(
    .WIDTH(12)
) closest_semitone_finder (
    .clk_in(clk_in),
    .rst_in(new_signal),
    .searching(phase == 1),
    .search_val(period),
    .closest_value(shifted_period_temp),
    .closest_value_found(search_valid_out)
);

always_comb begin
    if (offset < period) begin
        window_func_val = offset * inv_period; 
    end else begin
        window_func_val = 2 - offset * inv_period;
    end
end

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

    end else if (phase == 1) begin

        if (div_valid_out) begin
            inv_period_found <= 1;
            inv_period <= inv_period_temp;
        end

        if (search_valid_out) begin
            shifted_period_found <= 1;
            shifted_period <= shifted_period_temp;
        end

        if (inv_period_found && shifted_period_found) begin
            phase <= 1;
        end
    
    end else if (phase == 2 && i + period < WINDOW_SIZE) begin
        
        if (offset < 2 * period && offset < WINDOW_SIZE - i) begin

            if (j + offset >= output_window_len) begin
                output_window_len <= j + offset + 1;
            end

            if (j + offset < period) begin
                out[j + offset] <= $signed(signal[i + offset]); 
            end else begin
                out[j + offset] <= $signed(out[j + offset] + signal[i + offset] * window_func_val);
            end

            offset <= offset + 1;

        end else begin

            offset <= 0;
            i <= i + period;
            j <= j + shifted_period;

        end

    end else begin

        if (phase == 2) begin
            done <= 1;
        end
        phase <= 0;

    end

end



endmodule