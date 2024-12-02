module psola_no_bram #(parameter WINDOW_SIZE = 2048) (
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

logic [LOG_WINDOW_SIZE:0] i;
logic [LOG_WINDOW_SIZE:0] j;
logic [LOG_WINDOW_SIZE:0] offset;

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

logic [31:0] window_func_val_piped;
logic [31:0] signal_val_piped;
logic [31:0] processed_val_piped;

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


searcher closest_semitone_finder (
    .clk_in(clk_in),
    .rst_in(rst_in),
    .start_search(new_signal),
    .search_val(period),
    .closest_value(shifted_period_temp),
    .closest_value_found(search_valid_out)
);

always_comb begin
    if (offset < period) begin
        window_func_val = offset * inv_period; 
    end else begin
        window_func_val = (2 << 10) - offset * inv_period;
    end
end


logic [1:0] valid_write;
logic [31:0] write_val;
logic [LOG_WINDOW_SIZE:0] write_addr;
logic [LOG_WINDOW_SIZE:0] write_addr_piped;

always_ff @(posedge clk_in) begin

    if (valid_write[1] && !rst_in && !new_signal) begin
        out[write_addr_piped] <= write_val;
        valid_write[1] <= 0;
    end

    if (valid_write[0] && !rst_in && !new_signal) begin
        write_val <= processed_val_piped + signal_val_piped * window_func_val_piped;
        write_addr_piped <= write_addr;
        valid_write[1] <= 1;
    end


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
        valid_write <= 0;

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
        valid_write <= 0;

        for (integer i = 0; i < 2 * WINDOW_SIZE; i = i + 1) begin
            out[i] <= 0;
        end


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

        valid_write <= 0;
    
    end else if (phase == 2 && i + period < WINDOW_SIZE) begin
        
        if (offset < 2 * period && i + offset < WINDOW_SIZE) begin

            if (j + offset >= output_window_len) begin
                output_window_len <= j + offset + 1;
            end

            if (i + offset < period) begin
                window_func_val_piped <= (1 << 10);
                signal_val_piped <= $signed(signal[i + offset]); 
                processed_val_piped <= 0;
            end else begin
                window_func_val_piped <= window_func_val;
                signal_val_piped <= $signed(signal[i + offset]);
                processed_val_piped <= $signed(out[j + offset]);
            end

            write_addr <= j + offset;
            valid_write[0] <= 1;
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