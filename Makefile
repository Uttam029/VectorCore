.PHONY: test_matadd wave_matadd clean

# ==============================================================================
# Matrix Addition Kernel Simulation
# ==============================================================================

CORES ?= 2
THREADS_PER_BLOCK ?= 4
NUM_THREADS ?= 8

test_matadd:
	@echo "--- 1. Converting SystemVerilog to Verilog ---"
	sv2v -w build/gpu.v src/*.sv
	@echo "--- 2. Compiling with Icarus Verilog ---"
	iverilog -g2012 -P tb_matadd.NUM_CORES=$(CORES) -P tb_matadd.THREADS_PER_BLOCK=$(THREADS_PER_BLOCK) -P tb_matadd.NUM_THREADS=$(NUM_THREADS) -o build/matadd_sim.vvp build/gpu.v test/tb_matadd.v
	@echo "--- 3. Running Simulation ---"
	vvp build/matadd_sim.vvp

wave_matadd: test_matadd
	@echo "--- 4. Opening Waveform Viewer ---"
	gtkwave docs/matadd_waveform.vcd &

# ==============================================================================
# Clean
# ==============================================================================
clean:
	rm -rf build/*.v build/*.vvp docs/*.vcd docs/*.log
