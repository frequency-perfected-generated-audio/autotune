import os
import sys
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.clock import Clock
from cocotb.runner import get_runner
from cocotb.triggers import ClockCycles, FallingEdge, RisingEdge

# Parameters
WIDTH = 12
BRAM_SIZE = 256


# Helper Functions
async def reset(dut, cycles=5):
    """Reset the DUT."""
    dut.rst_in.value = 1
    await ClockCycles(dut.clk_in, cycles)
    dut.rst_in.value = 0


async def search_value(dut, search_val):
    """Search for the closest value."""
    await FallingEdge(dut.clk_in)
    dut.searching.value = 1
    dut.search_val.value = search_val
    await FallingEdge(dut.clk_in)
    dut.searching.value = 0


@cocotb.test()
async def test_searcher(dut):
    """Test the searcher module."""
    cocotb.start_soon(Clock(dut.clk_in, 10, units="ns").start())

    # Reset the DUT
    await reset(dut)

    # Test searching
    search_val = 234

    await FallingEdge(dut.clk_in)
    dut.search_val = search_val
    dut.searching.value = 1

    # for _ in range(25):
    #     dut._log.info(f"Bram val: {dut.val_from_bram.value.integer}")
    #     dut._log.info(f"Curr addr: {dut.curr_read_addr.value.integer}")
    #     dut._log.info(f"Valid out: {dut.closest_value_found.value.integer}")
    #     dut._log.info(f"Closest valu: {dut.closest_value.value.integer}")
    #     # dut._log.info(f"Searching: {dut.searching.value.integer}")
    #     dut._log.info("\n")
    #     await ClockCycles(dut.clk_in, 1)

    await RisingEdge(dut.closest_value_found)

    # Check results
    closest_value = dut.closest_value.value.integer
    closest_found = dut.closest_value_found.value
    assert closest_found, "Closest value not found."
    dut._log.info(f"Closest period found to {search_val} was {closest_value}")


def main():
    """Simulate the counter using the Python runner."""
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "sim" / "model"))
    sources = [proj_path / "hdl" / "searcher.sv"]
    sources += [proj_path / "hdl" / "xilinx_single_port_ram_read_first.sv"]
    build_test_args = ["-Wall"]
    parameters = {"WIDTH": WIDTH, "BRAM_SIZE": BRAM_SIZE}
    sys.path.append(str(proj_path / "sim"))
    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="searcher",
        always=True,
        build_args=build_test_args,
        parameters=parameters,
        timescale=("1ns", "1ps"),
        waves=True,
    )
    run_test_args = []
    runner.test(
        hdl_toplevel="searcher",
        test_module="test_searcher",
        test_args=run_test_args,
        waves=True,
    )


if __name__ == "__main__":
    main()
