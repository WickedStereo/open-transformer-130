module scratchpad #(
    parameter NUM_BANKS     = 8,
    parameter BANK_SIZE     = 16384,  // bytes per bank (16 KiB)
    parameter BANK_ADDR_W   = 14,     // log2(BANK_SIZE)
    parameter DATA_W        = 8
) (
    input  logic                                    clk,
    input  logic                                    rst_n,

    // Per-bank control (packed for Verilator/cocotb compatibility)
    input  logic [NUM_BANKS-1:0]                    bank_en,
    input  logic [NUM_BANKS-1:0]                    bank_wen,
    input  logic [NUM_BANKS*BANK_ADDR_W-1:0]        bank_addr,
    input  logic [NUM_BANKS*DATA_W-1:0]             bank_wdata,
    output logic [NUM_BANKS*DATA_W-1:0]             bank_rdata
);

    genvar gi;
    generate
        for (gi = 0; gi < NUM_BANKS; gi++) begin : gen_banks
            wire [BANK_ADDR_W-1:0] addr_i = bank_addr[gi*BANK_ADDR_W +: BANK_ADDR_W];
            wire [DATA_W-1:0]      wd_i   = bank_wdata[gi*DATA_W +: DATA_W];

            scratchpad_bank_1rw #(
                .BANK_SIZE   (BANK_SIZE),
                .BANK_ADDR_W (BANK_ADDR_W),
                .DATA_W      (DATA_W)
            ) u_bank (
                .clk   (clk),
                .en    (bank_en[gi]),
                .wen   (bank_wen[gi]),
                .addr  (addr_i),
                .wdata (wd_i),
                .rdata (bank_rdata[gi*DATA_W +: DATA_W])
            );
        end
    endgenerate

    logic _unused;
    assign _unused = &{1'b0, rst_n};

endmodule
