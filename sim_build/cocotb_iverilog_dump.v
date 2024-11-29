module cocotb_iverilog_dump();
initial begin
    $dumpfile("/Users/aarushgupta/School/6205/proj/autotune/sim_build/searcher.fst");
    $dumpvars(0, searcher);
end
endmodule
