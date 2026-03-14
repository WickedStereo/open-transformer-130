TOP ?= attention_stub
PYTHON ?= python3
VERILATOR ?= verilator
BUILD_DIR ?= build
RTL_SRCS := $(wildcard rtl/*.sv)
SIM_MAIN := sim/main.cpp
FPGA_SRC ?= rtl/attention_stub.sv
ICE40_ARCH ?=
ICE40_PACKAGE ?=

.PHONY: sim lint test fpga gds clean

sim: $(BUILD_DIR)/sim/V$(TOP)
	./$(BUILD_DIR)/sim/V$(TOP)

$(BUILD_DIR)/sim/V$(TOP): $(RTL_SRCS) $(SIM_MAIN)
	@if [ -z "$(RTL_SRCS)" ]; then echo "No SystemVerilog sources found in rtl/"; exit 1; fi
	mkdir -p $(BUILD_DIR)/sim
	$(VERILATOR) --cc --exe --build --sv -Wall --top-module $(TOP) --Mdir $(BUILD_DIR)/sim $(RTL_SRCS) $(SIM_MAIN)

lint:
	@if [ -z "$(RTL_SRCS)" ]; then echo "No SystemVerilog sources found in rtl/"; exit 1; fi
	$(VERILATOR) --lint-only --sv -Wall $(RTL_SRCS)

test:
	PYTHONPATH=$(CURDIR) $(PYTHON) -m pytest -q sim/

fpga:
	@if [ -z "$(ICE40_ARCH)" ] || [ -z "$(ICE40_PACKAGE)" ]; then \
		echo "Set ICE40_ARCH and ICE40_PACKAGE before running place-and-route."; \
		echo "Example: make fpga ICE40_ARCH=up5k ICE40_PACKAGE=sg48"; \
		exit 1; \
	fi
	mkdir -p $(BUILD_DIR)/fpga
	yosys -p 'read_verilog -sv $(FPGA_SRC); synth_ice40 -top $(TOP) -json $(BUILD_DIR)/fpga/$(TOP).json'
	nextpnr-ice40 --$(ICE40_ARCH) --package $(ICE40_PACKAGE) --json $(BUILD_DIR)/fpga/$(TOP).json --asc $(BUILD_DIR)/fpga/$(TOP).asc
	icepack $(BUILD_DIR)/fpga/$(TOP).asc $(BUILD_DIR)/fpga/$(TOP).bin

gds:
	@if [ -z "$(PDK_ROOT)" ]; then echo "Set PDK_ROOT before running OpenLane."; exit 1; fi
	openlane --pdk-root $(PDK_ROOT) openlane/config.json

clean:
	rm -rf $(BUILD_DIR) .pytest_cache sim/__pycache__ sim/*.fst sim/*.vcd sim/*.xml
