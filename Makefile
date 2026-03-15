TOP ?= attn_core
PYTHON ?= python3
VERILATOR ?= verilator
OPENLANE ?= $(PYTHON) -m openlane
DOCTOR ?= $(PYTHON) scripts/bootstrap_doctor.py
YOSYS ?= yosys
SMTBMC ?= yosys-smtbmc
FORMAL_SOLVER ?= cvc4
OPENLANE_RUN_DIR ?= $(CURDIR)
ifdef HOST_WORKSPACE
OPENLANE_RUN_DIR := $(HOST_WORKSPACE)
endif
OPENLANE_CONFIG ?= $(OPENLANE_RUN_DIR)/openlane/config.json
BUILD_DIR ?= build
FORMAL_BUILD_DIR ?= $(BUILD_DIR)/formal
RTL_SRCS := $(wildcard rtl/*.sv)
SIM_MAIN := sim/main.cpp
FPGA_SRC ?= $(RTL_SRCS)
ICE40_ARCH ?=
ICE40_PACKAGE ?=

.PHONY: doctor sim lint test formal formal-mac-lane formal-isa-decoder formal-dma-engine formal-tile-scheduler fpga-elab fpga gds clean

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
	$(VERILATOR) --lint-only --sv -Wall -Wno-MULTITOP -Wno-WIDTHTRUNC -Wno-UNUSEDSIGNAL $(RTL_SRCS)

test:
	PYTHONPATH=$(CURDIR) $(PYTHON) -m pytest -q sim/

formal: formal-mac-lane formal-isa-decoder formal-dma-engine formal-tile-scheduler

formal-mac-lane:
	mkdir -p $(FORMAL_BUILD_DIR)
	$(YOSYS) -q -p 'read_verilog -formal -sv rtl/mac_lane.sv formal/mac_lane_props.sv formal/mac_lane_formal.sv; prep -top mac_lane_formal; write_smt2 -wires $(FORMAL_BUILD_DIR)/mac_lane.smt2'
	$(SMTBMC) -s $(FORMAL_SOLVER) -t 20 $(FORMAL_BUILD_DIR)/mac_lane.smt2

formal-isa-decoder:
	mkdir -p $(FORMAL_BUILD_DIR)
	$(YOSYS) -q -p 'read_verilog -formal -sv rtl/isa_decoder.sv formal/isa_decoder_props.sv formal/isa_decoder_formal.sv; prep -top isa_decoder_formal; write_smt2 -wires $(FORMAL_BUILD_DIR)/isa_decoder.smt2'
	$(SMTBMC) -s $(FORMAL_SOLVER) -t 20 $(FORMAL_BUILD_DIR)/isa_decoder.smt2

formal-dma-engine:
	mkdir -p $(FORMAL_BUILD_DIR)
	$(YOSYS) -q -p 'read_verilog -formal -sv rtl/dma_engine.sv formal/dma_engine_props.sv formal/dma_engine_formal.sv; prep -top dma_engine_formal; write_smt2 -wires $(FORMAL_BUILD_DIR)/dma_engine.smt2'
	$(SMTBMC) -s $(FORMAL_SOLVER) -t 6 $(FORMAL_BUILD_DIR)/dma_engine.smt2

formal-tile-scheduler:
	mkdir -p $(FORMAL_BUILD_DIR)
	$(YOSYS) -q -p 'read_verilog -formal -sv rtl/tile_scheduler.sv formal/tile_scheduler_props.sv formal/tile_scheduler_formal.sv; prep -top tile_scheduler_formal; write_smt2 -wires $(FORMAL_BUILD_DIR)/tile_scheduler.smt2'
	$(SMTBMC) -s $(FORMAL_SOLVER) -t 30 $(FORMAL_BUILD_DIR)/tile_scheduler.smt2

fpga-elab:
	@if [ -z "$(FPGA_SRC)" ]; then echo "No FPGA sources configured."; exit 1; fi
	mkdir -p $(BUILD_DIR)/fpga
	$(YOSYS) -p 'read_verilog -sv $(FPGA_SRC); hierarchy -check -top $(TOP); stat -top $(TOP); write_json $(BUILD_DIR)/fpga/$(TOP)_hierarchy.json'

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
