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


async def store_values(dut, values):
    """Store values into the BRAM."""
    for value in values:
        await FallingEdge(dut.clk_in)
        dut.valid_store_val.value = 1
        dut.to_store_val.value = value
        await ClockCycles(dut.clk_in, 2)
        # dut._log.info(f"Current value OF ADDR: {dut.curr_store_addr.value.integer}")

    # Ensure valid_store_val is deasserted
    await FallingEdge(dut.clk_in)
    dut.valid_store_val.value = 0


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

    # Test storing values
    stored_values = [10, 20, 30, 40, 50]
    await store_values(dut, stored_values)
    dut._log.info(f"VALUE OF ADDR: {dut.curr_store_addr.value.integer}")
    assert dut.curr_store_addr.value.integer == len(
        stored_values
    ), "Incorrect store address after storing values."

    # Test searching
    search_val = 25

    await FallingEdge(dut.clk_in)
    dut.searching.value = 1

    for _ in range(25):
        dut._log.info(f"Bram val: {dut.val_from_bram.value.integer}")
        dut._log.info(f"Curr addr: {dut.curr_read_addr.value.integer}")
        await ClockCycles(dut.clk_in, 2)

    # Check results
    closest_value = dut.closest_value.value.integer
    closest_found = dut.closest_value_found.value
    assert closest_found, "Closest value not found."
    assert closest_value in stored_values, "Closest value is not in stored values."
    assert abs(closest_value - search_val) <= min(
        abs(val - search_val) for val in stored_values
    ), f"Closest value {closest_value} is not the closest to {search_val}."


def main():
    """Simulate the counter using the Python runner."""
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "sim" / "model"))
    sources = [proj_path / "hdl" / "searcher.sv"]
    sources += [proj_path / "hdl" / "xilinx_true_dual_port_read_first_1_clock_ram.v"]
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
