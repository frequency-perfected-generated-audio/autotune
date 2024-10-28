import os
import sys
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.runner import get_runner
from cocotb.triggers import ClockCycles, FallingEdge, ReadOnly, RisingEdge


async def reset(dut):
    await FallingEdge(dut.clk_in)
    dut.rst_in.value = 1
    await RisingEdge(dut.clk_in)
    await FallingEdge(dut.clk_in)
    dut.rst_in.value = 0
    await RisingEdge(dut.clk_in)


@cocotb.test()
async def test_ring_buffer(dut):
    def info(s):
        dut._log.info(s)

    async def c(i):
        await ClockCycles(dut.clk_in, i)

    async def f():
        await FallingEdge(dut.clk_in)

    async def r():
        await RisingEdge(dut.clk_in)

    info("Starting...")
    cocotb.start_soon(Clock(dut.clk_in, 10, units="ns").start())

    await reset(dut)

    await f()
    dut.shift_trigger.value = 0
    dut.read_trigger.value = 0
    await c(3)

    async def test(wrap):
        for i in range(8 + wrap):
            await f()
            dut.shift_trigger.value = 1
            dut.shift_data.value = i
            assert dut.shift_ready_out.value and dut.read_ready_out.value
            await r()
            await f()
            assert not dut.shift_ready_out.value and dut.read_ready_out.value
            dut.shift_trigger.value = 0

        for i in range(8):
            await f()
            dut.read_trigger.value = 1
            dut.read_addr.value = i
            # check previous iteration returned correct val
            if i > 0:
                assert dut.data_valid_out.value and dut.data_out == i - 1 + wrap
            assert dut.shift_ready_out.value and dut.read_ready_out.value
            await r()
            await f()
            assert dut.shift_ready_out.value and not dut.read_ready_out.value
            dut.read_trigger.value = 0

        await f()
        assert dut.data_valid_out.value and dut.data_out == 7 + wrap

    for i in range(7):
        await test(i)
    await test(8)

    await c(10)

    await ReadOnly()


def main():
    """Simulate the counter using the Python runner."""
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "sim" / "model"))
    sources = [
        proj_path / "hdl" / "ring_buffer.sv",
        proj_path / "hdl" / "xilinx_true_dual_port_read_first_1_clock_ram.v",
    ]
    build_test_args = ["-Wall"]
    parameters = {"ENTRIES": 8, "DATA_WIDTH": 4}
    sys.path.append(str(proj_path / "sim"))
    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="ring_buffer",
        always=True,
        build_args=build_test_args,
        parameters=parameters,
        timescale=("1ns", "1ps"),
        waves=True,
    )
    run_test_args = []
    runner.test(
        hdl_toplevel="ring_buffer",
        test_module="test_ring_buffer",
        test_args=run_test_args,
        waves=True,
    )


if __name__ == "__main__":
    main()
