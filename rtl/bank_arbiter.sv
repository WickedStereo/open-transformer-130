module bank_arbiter #(
    parameter NUM_BANKS   = 8,
    parameter ADDR_W      = 14,
    parameter DATA_W      = 8
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
    integer bank_comb_idx;
    integer bank_ff_reset_idx;
    integer bank_ff_idx;
    integer bank_rdata_idx;

    always_comb begin
        for (bank_comb_idx = 0; bank_comb_idx < NUM_BANKS; bank_comb_idx = bank_comb_idx + 1) begin
            dma_grant[bank_comb_idx]                      = 1'b0;
            mac_grant[bank_comb_idx]                      = 1'b0;
            vec_grant[bank_comb_idx]                      = 1'b0;
            bank_en[bank_comb_idx]                        = 1'b0;
            bank_wen_o[bank_comb_idx]                     = 1'b0;
            bank_addr_o[bank_comb_idx*ADDR_W +: ADDR_W]  = '0;
            bank_wdata_o[bank_comb_idx*DATA_W +: DATA_W] = '0;
            winner[bank_comb_idx]                         = 2'd0;
            arb_conflict[bank_comb_idx]                   = 1'b0;

            if (dma_req[bank_comb_idx]) begin
                dma_grant[bank_comb_idx]                      = 1'b1;
                bank_en[bank_comb_idx]                        = 1'b1;
                bank_wen_o[bank_comb_idx]                     = dma_wen[bank_comb_idx];
                bank_addr_o[bank_comb_idx*ADDR_W +: ADDR_W]  = dma_addr[bank_comb_idx*ADDR_W +: ADDR_W];
                bank_wdata_o[bank_comb_idx*DATA_W +: DATA_W] = dma_wdata[bank_comb_idx*DATA_W +: DATA_W];
                winner[bank_comb_idx]                         = 2'd1;
                arb_conflict[bank_comb_idx]                   = mac_req[bank_comb_idx] | vec_req[bank_comb_idx];
            end else if (mac_req[bank_comb_idx]) begin
                mac_grant[bank_comb_idx]                      = 1'b1;
                bank_en[bank_comb_idx]                        = 1'b1;
                bank_wen_o[bank_comb_idx]                     = mac_wen[bank_comb_idx];
                bank_addr_o[bank_comb_idx*ADDR_W +: ADDR_W]  = mac_addr[bank_comb_idx*ADDR_W +: ADDR_W];
                bank_wdata_o[bank_comb_idx*DATA_W +: DATA_W] = mac_wdata[bank_comb_idx*DATA_W +: DATA_W];
                winner[bank_comb_idx]                         = 2'd2;
                arb_conflict[bank_comb_idx]                   = vec_req[bank_comb_idx];
            end else if (vec_req[bank_comb_idx]) begin
                vec_grant[bank_comb_idx]                      = 1'b1;
                bank_en[bank_comb_idx]                        = 1'b1;
                bank_wen_o[bank_comb_idx]                     = vec_wen[bank_comb_idx];
                bank_addr_o[bank_comb_idx*ADDR_W +: ADDR_W]  = vec_addr[bank_comb_idx*ADDR_W +: ADDR_W];
                bank_wdata_o[bank_comb_idx*DATA_W +: DATA_W] = vec_wdata[bank_comb_idx*DATA_W +: DATA_W];
                winner[bank_comb_idx]                         = 2'd3;
            end
        end
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            for (bank_ff_reset_idx = 0; bank_ff_reset_idx < NUM_BANKS; bank_ff_reset_idx = bank_ff_reset_idx + 1)
                winner_r[bank_ff_reset_idx] <= 2'd0;
        end else begin
            for (bank_ff_idx = 0; bank_ff_idx < NUM_BANKS; bank_ff_idx = bank_ff_idx + 1)
                winner_r[bank_ff_idx] <= winner[bank_ff_idx];
        end
    end

    always_comb begin
        dma_rdata = '0;
        mac_rdata = '0;
        vec_rdata = '0;
        for (bank_rdata_idx = 0; bank_rdata_idx < NUM_BANKS; bank_rdata_idx = bank_rdata_idx + 1) begin
            case (winner_r[bank_rdata_idx])
                2'd1: dma_rdata[bank_rdata_idx*DATA_W +: DATA_W] = bank_rdata_i[bank_rdata_idx*DATA_W +: DATA_W];
                2'd2: mac_rdata[bank_rdata_idx*DATA_W +: DATA_W] = bank_rdata_i[bank_rdata_idx*DATA_W +: DATA_W];
                2'd3: vec_rdata[bank_rdata_idx*DATA_W +: DATA_W] = bank_rdata_i[bank_rdata_idx*DATA_W +: DATA_W];
                default: ;
            endcase
        end
    end

endmodule
