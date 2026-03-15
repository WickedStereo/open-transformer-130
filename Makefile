TOP ?= attention_stub
PYTHON ?= python3
VERILATOR ?= verilator
OPENLANE ?= $(PYTHON) -m openlane
DOCTOR ?= $(PYTHON) scripts/bootstrap_doctor.py
OPENLANE_RUN_DIR ?= $(CURDIR)
ifdef HOST_WORKSPACE
OPENLANE_RUN_DIR := $(HOST_WORKSPACE)
endif
OPENLANE_CONFIG ?= $(OPENLANE_RUN_DIR)/openlane/config.json
BUILD_DIR ?= build
RTL_SRCS := $(wildcard rtl/*.sv)
SIM_MAIN := sim/main.cpp
FPGA_SRC ?= rtl/attention_stub.sv
ICE40_ARCH ?=
ICE40_PACKAGE ?=

.PHONY: doctor sim lint test fpga gds clean

doctor:
	$(DOCTOR)

sim: $(BUILD_DIR)/sim/V$(TOP)
	./$(BUILD_DIR)/sim/V$(TOP)

$(BUILD_DIR)/sim/V$(TOP): $(RTL_SRCS) $(SIM_MAIN)
	@if [ -z "$(RTL_SRCS)" ]; then echo "No SystemVerilog sources found in rtl/"; exit 1; fi
	mkdir -p $(BUILD_DIR)/sim
	$(VERILATOR) --cc --exe --build --sv -Wall --top-module $(TOP) --Mdir $(BUILD_DIR)/sim $(RTL_SRCS) $(SIM_MAIN)

lint:
	@if [ -z "$(RTL_SRCS)" ]; then echo "No SystemVerilog sources found in rtl/"; exit 1; fi
	$(VERILATOR) --lint-only --sv -Wall -Wno-MULTITOP $(RTL_SRCS)

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
	@if docker info >/dev/null 2>&1; then \
		cd "$(OPENLANE_RUN_DIR)" && $(OPENLANE) --docker-no-tty --dockerized --pdk-root "$(PDK_ROOT)" "$(OPENLANE_CONFIG)"; \
	elif sudo docker info >/dev/null 2>&1; then \
		sudo -E bash -lc 'cd "$(OPENLANE_RUN_DIR)" && $(OPENLANE) --docker-no-tty --dockerized --pdk-root "$(PDK_ROOT)" "$(OPENLANE_CONFIG)"'; \
	else \
		echo "Docker is not accessible from this shell."; \
		exit 1; \
	fi

clean:
	@for path in "$(BUILD_DIR)" "openlane/runs" ".pytest_cache" "sim/__pycache__"; do \
		if [ -e "$$path" ]; then \
			rm -rf "$$path" 2>/dev/null || docker run --rm -v "$(CURDIR):/repo" busybox sh -c "rm -rf /repo/$$path"; \
		fi; \
	done
	@rm -f sim/*.fst sim/*.vcd sim/*.xml
