module cocotb_iverilog_dump();
initial begin
    $dumpfile("/Users/aarushgupta/School/6205/proj/autotune/sim_build/psola.fst");
    $dumpvars(0, psola);
end
endmodule
