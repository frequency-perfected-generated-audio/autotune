import os
import sys
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.runner import get_runner
from cocotb.triggers import ClockCycles, FallingEdge, ReadOnly, RisingEdge


def get_bit(data, n):
    return (data >> n) & 1


async def reset(dut):
    await FallingEdge(dut.clk_in)
    dut.rst_in.value = 1
    await ClockCycles(dut.clk_in, 10)
    dut.rst_in.value = 0
    await RisingEdge(dut.clk_in)


async def test_data_receive(dut):
    await FallingEdge(dut.clk_in)
    dut.rst_in.value = 1
    await ClockCycles(dut.clk_in, 10)
    dut.rst_in.value = 0

    datas = [
        0xC0FFEE,
        0x696969,
        0x424242,
        0xBAB1E5,
        0x123456,
        0xCAFE55,
        0xDECAF5,
        0xDEADBF,
        0xBEEFED,
        0x192837,
    ]
    for i in range(10):
        data = datas[i]
        await ClockCycles(dut.clk_in, 1)
        await FallingEdge(dut.clk_in)
        assert dut.ws_out == 0

        await FallingEdge(dut.sclk_out)  # wait one sclk

        for i in range(23, -1, -1):
            dut.sdata_in.value = get_bit(data, i)
            if i != 0:
                await FallingEdge(dut.sclk_out)

        # wait until posedge of sclk for data to get picked up
        await RisingEdge(dut.sclk_out)

        # data comes out one cycle later
        await ClockCycles(dut.clk_in, 1)
        await FallingEdge(dut.clk_in)  # sample on negedge so cocotb picks it up
        assert dut.data_valid_out.value == 1
        assert dut.data_out.value == data >> 8

        # data_valid_out should only be valid for one cycle
        await ClockCycles(dut.clk_in, 1)
        await FallingEdge(dut.clk_in)  # sample on negedge so cocotb picks it up
        assert dut.data_valid_out.value == 0

        # check that ws transitions correctly
        for i in range(8):
            await FallingEdge(dut.sclk_out)
        await ClockCycles(dut.clk_in, 1)
        assert dut.ws_out == 1

        # wait out other channel (we ignore this data)
        for i in range(32):
            await FallingEdge(dut.sclk_out)


@cocotb.test()
async def test_i2s_receiver(dut):
    def info(s):
        dut._log.info(s)

    info("Starting...")
    cocotb.start_soon(Clock(dut.clk_in, 10, units="ns").start())

    await reset(dut)

    await test_data_receive(dut)

    # await ClockCycles(dut.clk_in, 5000)


def main():
    """Simulate the counter using the Python runner."""
    sim = os.getenv("SIM", "icarus")
    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "sim" / "model"))
    sources = [proj_path / "hdl" / "i2s_receiver.sv"]
    build_test_args = ["-Wall"]
    parameters = {}
    sys.path.append(str(proj_path / "sim"))
    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="i2s_receiver",
        always=True,
        build_args=build_test_args,
        parameters=parameters,
        timescale=("1ns", "1ps"),
        waves=True,
    )
    run_test_args = []
    runner.test(
        hdl_toplevel="i2s_receiver",
        test_module="test_i2s_receiver",
        test_args=run_test_args,
        waves=True,
    )


if __name__ == "__main__":
    main()
