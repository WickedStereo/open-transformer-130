module bank_arbiter #(
    parameter int NUM_BANKS   = 8,
    parameter int ADDR_W      = 14,
    parameter int DATA_W      = 8
) (
    input  logic clk,
    input  logic rst_n,

    // DMA requester (highest priority) -- packed per-bank signals
    input  logic [NUM_BANKS-1:0]              dma_req,
    input  logic [NUM_BANKS*ADDR_W-1:0]       dma_addr,
    input  logic [NUM_BANKS-1:0]              dma_wen,
    input  logic [NUM_BANKS*DATA_W-1:0]       dma_wdata,
    output logic [NUM_BANKS-1:0]              dma_grant,
    output logic [NUM_BANKS*DATA_W-1:0]       dma_rdata,

    // MAC requester (medium priority)
    input  logic [NUM_BANKS-1:0]              mac_req,
    input  logic [NUM_BANKS*ADDR_W-1:0]       mac_addr,
    input  logic [NUM_BANKS-1:0]              mac_wen,
    input  logic [NUM_BANKS*DATA_W-1:0]       mac_wdata,
    output logic [NUM_BANKS-1:0]              mac_grant,
    output logic [NUM_BANKS*DATA_W-1:0]       mac_rdata,

    // Vector requester (lowest priority)
    input  logic [NUM_BANKS-1:0]              vec_req,
    input  logic [NUM_BANKS*ADDR_W-1:0]       vec_addr,
    input  logic [NUM_BANKS-1:0]              vec_wen,
    input  logic [NUM_BANKS*DATA_W-1:0]       vec_wdata,
    output logic [NUM_BANKS-1:0]              vec_grant,
    output logic [NUM_BANKS*DATA_W-1:0]       vec_rdata,

    // Scratchpad bank ports
    output logic [NUM_BANKS-1:0]              bank_en,
    output logic [NUM_BANKS-1:0]              bank_wen_o,
    output logic [NUM_BANKS*ADDR_W-1:0]       bank_addr_o,
    output logic [NUM_BANKS*DATA_W-1:0]       bank_wdata_o,
    input  logic [NUM_BANKS*DATA_W-1:0]       bank_rdata_i,

    output logic [NUM_BANKS-1:0]              arb_conflict
);

    // Track which requester won each bank (for read-data routing)
    logic [1:0] winner [NUM_BANKS];
    logic [1:0] winner_r [NUM_BANKS];

    always_comb begin
        for (int b = 0; b < NUM_BANKS; b++) begin
            dma_grant[b]                        = 1'b0;
            mac_grant[b]                        = 1'b0;
            vec_grant[b]                        = 1'b0;
            bank_en[b]                          = 1'b0;
            bank_wen_o[b]                       = 1'b0;
            bank_addr_o[b*ADDR_W +: ADDR_W]    = '0;
            bank_wdata_o[b*DATA_W +: DATA_W]   = '0;
            winner[b]                           = 2'd0;
            arb_conflict[b]                     = 1'b0;

            if (dma_req[b]) begin
                dma_grant[b]                      = 1'b1;
                bank_en[b]                        = 1'b1;
                bank_wen_o[b]                     = dma_wen[b];
                bank_addr_o[b*ADDR_W +: ADDR_W]  = dma_addr[b*ADDR_W +: ADDR_W];
                bank_wdata_o[b*DATA_W +: DATA_W] = dma_wdata[b*DATA_W +: DATA_W];
                winner[b]                         = 2'd1;
                arb_conflict[b]                   = mac_req[b] | vec_req[b];
            end else if (mac_req[b]) begin
                mac_grant[b]                      = 1'b1;
                bank_en[b]                        = 1'b1;
                bank_wen_o[b]                     = mac_wen[b];
                bank_addr_o[b*ADDR_W +: ADDR_W]  = mac_addr[b*ADDR_W +: ADDR_W];
                bank_wdata_o[b*DATA_W +: DATA_W] = mac_wdata[b*DATA_W +: DATA_W];
                winner[b]                         = 2'd2;
                arb_conflict[b]                   = vec_req[b];
            end else if (vec_req[b]) begin
                vec_grant[b]                      = 1'b1;
                bank_en[b]                        = 1'b1;
                bank_wen_o[b]                     = vec_wen[b];
                bank_addr_o[b*ADDR_W +: ADDR_W]  = vec_addr[b*ADDR_W +: ADDR_W];
                bank_wdata_o[b*DATA_W +: DATA_W] = vec_wdata[b*DATA_W +: DATA_W];
                winner[b]                         = 2'd3;
            end
        end
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            for (int b = 0; b < NUM_BANKS; b++)
                winner_r[b] <= 2'd0;
        end else begin
            for (int b = 0; b < NUM_BANKS; b++)
                winner_r[b] <= winner[b];
        end
    end

    always_comb begin
        dma_rdata = '0;
        mac_rdata = '0;
        vec_rdata = '0;
        for (int b = 0; b < NUM_BANKS; b++) begin
            case (winner_r[b])
                2'd1: dma_rdata[b*DATA_W +: DATA_W] = bank_rdata_i[b*DATA_W +: DATA_W];
                2'd2: mac_rdata[b*DATA_W +: DATA_W] = bank_rdata_i[b*DATA_W +: DATA_W];
                2'd3: vec_rdata[b*DATA_W +: DATA_W] = bank_rdata_i[b*DATA_W +: DATA_W];
                default: ;
            endcase
        end
    end

endmodule
