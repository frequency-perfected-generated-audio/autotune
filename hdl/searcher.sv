module searcher #(
    parameter WIDTH = 12,
    parameter BRAM_SIZE = 256
) (
    input logic clk_in,
    input logic rst_in,
    input logic valid_store_val,
    input logic [WIDTH - 1:0] to_store_val,
    input logic searching,
    input logic [WIDTH - 1:0] search_val,
    output logic [WIDTH - 1:0] closest_value,
    output logic closest_value_found
);

    logic cycle_parity;
    
    logic [$clog2(BRAM_SIZE) - 1: 0] curr_store_addr;

    logic [$clog2(BRAM_SIZE) - 1: 0] curr_read_addr;
    logic [WIDTH-1:0] prev_diff;
    logic [WIDTH-1:0] val_from_bram;

    xilinx_true_dual_port_read_first_1_clock_ram #(
        .RAM_WIDTH(WIDTH),
        .RAM_DEPTH(BRAM_SIZE),
        .RAM_PERFORMANCE("HIGH_PERFORMANCE")
    ) diff_bram (
        .clka (clk_in),

        .addra(curr_store_addr),
        .wea  (valid_store_val && !cycle_parity),
        .dina (to_store_val),
        .douta(),
        .rsta(rst_in),

        .addrb(curr_read_addr),
        .web(0),
        .dinb(),
        .doutb(val_from_bram),
        .rstb(rst_in),

        .ena(1'b1),
        .enb(1'b1),
        .regcea(1'b1),
        .regceb(1'b1)
    );

    always_ff @(posedge clk_in) begin
        if (rst_in) begin

            cycle_parity <= 0;

            curr_store_addr <= 0;
            curr_read_addr <= 0;
            prev_diff <= {WIDTH{1'b1}};

            closest_value <= 0;
            closest_value_found <= 0;

        end else if (!cycle_parity) begin

            if (closest_value_found) begin
                // RESET SEARCH
                curr_store_addr <= 0;
                curr_read_addr <= 0;
                prev_diff <= {WIDTH{1'b1}};

                closest_value <= 0;
                closest_value_found <= 0;
            end

            if (valid_store_val) begin

                curr_store_addr <= curr_store_addr + 1;

            end else if (searching) begin

                if (val_from_bram > search_val) begin

                    if (prev_diff > val_from_bram - search_val) begin
                        closest_value <= val_from_bram;
                    end else begin
                        closest_value <= search_val - prev_diff; 
                    end

                    closest_value_found <= 1;

                end else begin

                    prev_diff <= search_val - val_from_bram;
                    curr_read_addr <= curr_read_addr + 1;

                end

            end

            cycle_parity <= 1;

        end else begin
            cycle_parity <= 0;
        end
    end

endmodule