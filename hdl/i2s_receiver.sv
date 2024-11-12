`default_nettype none

module i2s_receiver (
    input wire clk_in,
    input wire rst_in,

    // I2S inputs
    input logic sdata_in,

    // I2S Outputs
    output logic sclk_out,
    output logic ws_out,

    // Data Outputs
    output logic [15:0] data_out,
    output logic data_valid_out
);

    localparam int I2S_PERIOD = 64;
    localparam int I2S_HALF_PERIOD = I2S_PERIOD / 2;
    localparam int SCLK_PERIOD = 36;  // 10^8/(44100*64) = 35.43 -> round up
    localparam int SCLK_HALF_PERIOD = SCLK_PERIOD / 2;

    logic [$clog2(SCLK_PERIOD)-1:0] sclk_cycle;
    logic [7:0] cycle;

    // Outputs
    logic sclk;
    logic ws;
    logic [23:0] sdata;
    always_comb begin
        sclk_out = sclk;
        ws_out   = ws;
        data_out = sdata[23:8];
    end

    always_ff @(posedge clk_in) begin
        if (rst_in) begin
            sclk <= 1;  // sclk starts high
            ws <= 0;

            // Start at end of an I2S period so we reset "into" a new I2S period
            sclk_cycle <= SCLK_PERIOD - 1;
            cycle <= I2S_PERIOD - 1;
        end else begin
            // sclk output
            if (sclk_cycle == SCLK_HALF_PERIOD - 1) begin
                sclk <= 1;
            end else if (sclk_cycle == SCLK_PERIOD - 1) begin
                sclk <= 0;
            end

            // sclk period
            if (sclk_cycle == SCLK_PERIOD - 1) begin
                sclk_cycle <= 0;
            end else begin
                sclk_cycle <= sclk_cycle + 1;
            end

            // I2S period
            if (sclk_cycle == SCLK_PERIOD - 1) begin
                if (cycle == I2S_PERIOD - 1) begin
                    cycle <= 0;
                    ws <= 0;
                end else begin
                    if (cycle == I2S_HALF_PERIOD - 1) begin
                        ws <= 1;
                    end
                    cycle <= cycle + 1;
                end
            end

            // Read in data on halfway point of sclk (happens to be rising edge)
            if (1 <= cycle && cycle <= 24 && sclk_cycle == SCLK_HALF_PERIOD - 1) begin
                sdata <= {sdata[22:0], sdata_in};
            end

            // Output data one (FPGA) cycle after last bit is received
            if (cycle == 24 && sclk_cycle == SCLK_HALF_PERIOD) begin
                data_valid_out <= 1;
            end else begin
                data_valid_out <= 0;
            end
        end
    end
endmodule


`default_nettype wire
