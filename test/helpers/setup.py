from typing import List
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge
from .memory import Memory

async def setup(
    dut, 
    program_memory: Memory, 
    program: List[int],
    data_memory: Memory,
    data: List[int],
    threads: int
):
    """Initialize the GPU for kernel execution.
    
    Steps:
    1. Start the clock (25us period)
    2. Reset the GPU
    3. Load program instructions into program memory
    4. Load input data into data memory
    5. Set thread count in the Device Control Register
    6. Assert the start signal to begin kernel execution
    """
    # Setup Clock
    clock = Clock(dut.clk, 25, units="us")
    cocotb.start_soon(clock.start())

    # Reset
    dut.reset.value = 1
    await RisingEdge(dut.clk)
    dut.reset.value = 0

    # Load Program Memory
    program_memory.load(program)

    # Load Data Memory
    data_memory.load(data)

    # Device Control Register - set thread count
    dut.device_control_write_enable.value = 1
    dut.device_control_data.value = threads
    await RisingEdge(dut.clk)
    dut.device_control_write_enable.value = 0

    # Start kernel execution
    dut.start.value = 1
