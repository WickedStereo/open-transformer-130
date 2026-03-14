#include <iostream>
#include <memory>

#include "Vattention_stub.h"
#include "verilated.h"

namespace {

void tick(Vattention_stub* dut) {
    dut->clk = 0;
    dut->eval();
    dut->clk = 1;
    dut->eval();
}

}  // namespace

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);

    auto dut = std::make_unique<Vattention_stub>();
    dut->clk = 0;
    dut->reset = 1;
    dut->valid_in = 0;
    dut->query_in = 0;
    dut->key_in = 0;
    dut->value_in = 0;

    tick(dut.get());

    dut->reset = 0;
    dut->valid_in = 1;
    dut->query_in = 3;
    dut->key_in = 4;
    dut->value_in = 7;

    tick(dut.get());

    dut->valid_in = 0;
    tick(dut.get());

    std::cout << "valid_out=" << static_cast<int>(dut->valid_out)
              << " score_out=" << dut->score_out
              << " value_out=" << dut->value_out << std::endl;

    return 0;
}
