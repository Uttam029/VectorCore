.PHONY: test_matadd wave_matadd clean

# ==============================================================================
# Matrix Addition Kernel Simulation
# ==============================================================================

test_matadd:
	@echo "--- 1. Converting SystemVerilog to Verilog ---"
	sv2v -w build/gpu.v src/*.sv
	@echo "--- 2. Compiling with Icarus Verilog ---"
	iverilog -g2012 -o build/matadd_sim.vvp build/gpu.v test/tb_matadd.v
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
