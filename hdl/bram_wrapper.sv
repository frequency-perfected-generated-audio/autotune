module bram_wrapper #(
    parameter WINDOW_SIZE = 2048,
    parameter MAX_EXTENDED = 2200
) (
    input logic clk_in,
    input logic rst_in,

    input logic new_signal,
    input logic [11:0] period,

    // gets next window of input while running psola on current
    input logic [31:0] next_window_val,
    input logic [$clog2(WINDOW_SIZE) - 1:0] val_addr,
    input logic valid_in_val,

    output logic [31:0] out_val,
    output logic [$clog2(MAX_EXTENDED) - 1:0] out_addr_piped,
    output logic valid_out_piped,

    output logic done
)

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

logic [LOG_WINDOW_SIZE:0] psola_read_addr;
logic [LOG_WINDOW_SIZE:0] psola_write_addr;

logic [31:0] psola_write_val;
logic [31:0] psola_write_addr_piped;
logic psola_valid_write;

logic [$clog2(MAX_EXTENDED)-1:0] psola_output_window_len;

// BRAM output registers


logic [$clog2(MAX_EXTENDED) - 1:0] out_addr;
logic valid_out;


// BRAM storing signal values for current and next window
// PORT A used for getting next window of input, PORT B used to read curr window into PSOLA
xilinx_true_dual_port_read_first_1_clock_ram #(
  .RAM_WIDTH(32),
  .RAM_DEPTH(2 * WINDOW_SIZE),
  .RAM_PERFORMANCE("HIGH_PERFORMANCE")
) signal_bram (
  .addra(window_parity ? val_addr + WINDOW_SIZE : val_addr),
  .addrb(window_parity ? psola_read_addr : psola_read_addr + WINDOW_SIZE), 
  .dina(next_window_val),
  .dinb(0), 
  .clka(clk_in),             
  .wea(valid_in_val),           
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
    .douta((phase == 0) ? psola_in_curr_processed_val : out_val),  
    .doutb()  
)

psola #(
    .WINDOW_SIZE(WINDOW_SIZE)
) psola_inst (
    .clk_in(clk_in),
    .rst_in(rst_in),
    .new_signal(new_signal),
    .period(period),
    .signal(psola_in_signal_val),
    .curr_processed_val(psola_in_curr_processed_val),
    .read_addr(psola_read_addr),
    .write_addr(psola_write_addr),
    .write_val(psola_write_val),
    .write_addr_piped(psola_write_addr_piped),
    .valid_write(psola_valid_write),
    .output_window_len(psola_output_window_len),
    .done(psola_done)
);

always_ff @(posedge clk_in) begin

    if (rst_in) begin

        window_parity <= 0;

        phase <= 0;
        done <= 0;
        read_done <= 0;
        output_done <= 0;

    end else if (output_done && read_done) begin

        phase <= 0;
        done <= 1;

    end else if (new_signal) begin

        window_parity <= ~window_parity;
        phase <= 0;
        read_done <= 0;
        output_done <= 0;

    end else if (phase == 0) begin

        if (psola_done) begin
            phase <= 1;
        end

    end else if (phase == 1) begin

        out_addr <= out_addr + 1;
        valid_out <= 1;

    end

    if (val_addr == WINDOW_SIZE - 1 && valid_in_val) begin
        read_done <= 1;
    end

    if (phase == 1 && out_addr_piped == psola_output_window_len - 1) begin
        output_done <= 1;
    end

end

endmodule