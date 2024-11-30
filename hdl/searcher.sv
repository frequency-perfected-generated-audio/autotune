`ifdef SYNTHESIS
`define FPATH(X) `"X`"
`else /* ! SYNTHESIS */
`define FPATH(X) `"../../data/X`"
`endif  /* ! SYNTHESIS */

module searcher #(
    parameter WIDTH = 12,
    parameter BRAM_SIZE = 64
) (
    input logic clk_in,
    input logic rst_in,
    input logic start_search,
    input logic [WIDTH - 1:0] search_val,
    output logic [WIDTH - 1:0] closest_value,
    output logic closest_value_found
);

    logic cycle_parity;
    logic searching;
    
    logic [$clog2(BRAM_SIZE): 0] curr_read_addr;
    logic [WIDTH-1:0] prev_diff;
    logic [WIDTH-1:0] val_from_bram;

    xilinx_single_port_ram_read_first #(
    .RAM_WIDTH(WIDTH),                       
    .RAM_DEPTH(BRAM_SIZE),                     
    .RAM_PERFORMANCE("HIGH_PERFORMANCE"),
    // .INIT_FILE(`FPATH(semitones.mem))
    .INIT_FILE("/Users/aarushgupta/School/6205/proj/autotune/data/semitones.mem")
    ) freqs_ram (
        .addra(curr_read_addr),
        .dina(0),
        .clka(clk_in),
        .wea(0),      
        .ena(1),      
        .rsta(rst_in),
        .regcea(1), 
        .douta(val_from_bram)
    );

    always_ff @(posedge clk_in) begin
        if (rst_in) begin

            cycle_parity <= 0;

            curr_read_addr <= 0;
            prev_diff <= {WIDTH{1'b1}};

            searching <= 0;

            closest_value <= 0;
            closest_value_found <= 0;

        end else if (start_search) begin

            searching <= 1;
            cycle_parity <= 0;
            curr_read_addr <= 0;
            prev_diff <= {WIDTH{1'b1}};

            closest_value <= 0;
            closest_value_found <= 0;

        end
        
        else if (!cycle_parity) begin

            if (closest_value_found) begin

                // RESET SEARCH
                curr_read_addr <= 0;
                prev_diff <= {WIDTH{1'b1}};

                closest_value <= 0;
                closest_value_found <= 0;
                searching <= 0;

            end else if (searching) begin

                if (val_from_bram >= search_val) begin

                    if (prev_diff > val_from_bram - search_val) begin
                        closest_value <= val_from_bram;
                    end else begin
                        closest_value <= search_val - prev_diff; 
                    end

                    closest_value_found <= 1;

                end else if (curr_read_addr == BRAM_SIZE) begin

                    closest_value <= val_from_bram;
                    closest_value_found <= 1;

                end
                
                else begin

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