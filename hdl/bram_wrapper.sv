`default_nettype none
module bram_wrapper #(
    parameter WINDOW_SIZE = 2048,
    parameter MAX_EXTENDED = 2200
) (
    input logic clk_in,
    input logic rst_in,

    // YIN output
    input logic tau_valid_in,
    input logic [11:0] tau_in,

    // gets next window of input while running psola on current
    input logic signed [31:0] sample_in,
    input logic [$clog2(WINDOW_SIZE) - 1:0] addr_in,
    input logic sample_valid_in,

    output logic signed [31:0] out_val,
    output logic [$clog2(MAX_EXTENDED) - 1:0] out_addr_piped,
    output logic valid_out_piped,

    output logic done
);

// determines which portion BRAM to write to, alternates
// parity 0 indicates using first half for psola, writing to second half; vice versa
logic window_parity; 

// State logic
logic psola_done;
logic output_done;
logic read_done;
logic [1:0] phase;  // 0: psola, 1: output, 2: idle; reading happens in parallel

// PSOLA module I/O registers
logic [31:0] psola_in_signal_val;
logic [31:0] psola_in_curr_processed_val;

logic [$clog2(WINDOW_SIZE) - 1:0] psola_read_addr;
logic [$clog2(MAX_EXTENDED) - 1:0] psola_write_addr;

logic [31:0] psola_write_val;
logic [31:0] psola_write_addr_piped;
logic psola_valid_write;

logic [$clog2(MAX_EXTENDED)-1:0] psola_output_window_len;

// BRAM output registers

logic [$clog2(MAX_EXTENDED) - 1:0] out_addr;
logic valid_out;

// Pipelined output registers

pipeline #(
    .STAGES(2),
    .WIDTH(1)
) valid_out_pipeline (
    .clk(clk_in),
    .rst(rst_in),
    .din(valid_out),
    .dout(valid_out_piped)
);

pipeline #(
    .STAGES(2),
    .WIDTH($clog2(MAX_EXTENDED))
) out_addr_pipeline (
    .clk(clk_in),
    .rst(rst_in),
    .din(out_addr),
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
    .addrb(psola_write_addr_piped),
    .dina(0), 
    .dinb(psola_write_val),
    .clka(clk_in),             
    .wea(phase == 1),           
    .web(psola_valid_write),                 
    .ena(1),                   
    .enb(1),                  
    .rsta(rst_in),              
    .rstb(rst_in),             
    .regcea(1),          
    .regceb(1),         
    .douta(out_val),  
    .doutb()  
);

assign psola_in_curr_processed_val = out_val; 

psola #(
    .WINDOW_SIZE(WINDOW_SIZE)
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
  .RAM_WIDTH(32),
  .RAM_DEPTH(2 * WINDOW_SIZE),
  .RAM_PERFORMANCE("HIGH_PERFORMANCE")
) signal_bram (
  .addra(window_parity ? addr_in + WINDOW_SIZE : addr_in),
  .addrb(window_parity ? psola_read_addr : psola_read_addr + WINDOW_SIZE), 
  .dina(sample_in),
  .dinb(0), 
  .clka(clk_in),             
  .wea(sample_valid_in),           
  .web(0),                 
  .ena(1),                   
  .enb(1),                  
  .rsta(rst_in),              
  .rstb(rst_in),             
  .regcea(1),          
  .regceb(1),         
  .douta(),  
  .doutb(psola_in_signal_val)
);


always_ff @(posedge clk_in) begin

    if (rst_in) begin

        window_parity <= 0;

        phase <= 0;
        done <= 0;
        read_done <= 0;
        output_done <= 0;

        valid_out <= 0;
        out_addr <= 0;

    end else if (tau_valid_in) begin

        window_parity <= ~window_parity;
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

    end else if (phase == 1) begin

        if (out_addr_piped == psola_output_window_len - 1) begin
            output_done <= 1;
            valid_out <= 0;
        end else if (out_addr < psola_output_window_len - 1) begin
            out_addr <= out_addr + 1;
            valid_out <= 1;
        end else begin
            valid_out <= 0;
        end


    end

    if (addr_in == WINDOW_SIZE - 1 && sample_valid_in) begin
        read_done <= 1;
    end

    

end

endmodule
