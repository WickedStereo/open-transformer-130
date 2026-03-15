module dma_engine_formal;
    (* gclk *) logic clk;

    logic rst_n;
    logic f_past_valid;

    (* anyseq *) logic        cmd_valid;
    (* anyseq *) logic        cmd_load;
    (* anyseq *) logic [31:0] cmd_host_addr;
    (* anyseq *) logic [4:0]  cmd_slot_id;
    (* anyseq *) logic [12:0] cmd_byte_count;
    (* anyseq *) logic [127:0] bus_rdata;
    (* anyseq *) logic [63:0]  scratch_rdata_seed;

    logic        cmd_ready;
    logic        done;
    logic        error;
    logic [31:0] bytes_moved;
    logic        bus_req;
    logic [31:0] bus_addr;
    logic        bus_wen;
    logic [127:0] bus_wdata;
    logic        bus_ack;
    logic [7:0]  scratch_req;
    logic [8*14-1:0] scratch_addr;
    logic [7:0]  scratch_wen;
    logic [8*8-1:0] scratch_wdata;
    logic [7:0]  scratch_grant;
    logic [8*8-1:0] scratch_rdata;

    initial f_past_valid = 1'b0;

    always_ff @(posedge clk) begin
        f_past_valid <= 1'b1;
    end

    assign rst_n = f_past_valid;
    assign bus_ack = bus_req;
    assign scratch_grant = scratch_req;
    assign scratch_rdata = {8{scratch_rdata_seed[7:0]}};

    dma_engine dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .cmd_valid      (cmd_valid),
        .cmd_ready      (cmd_ready),
        .cmd_load       (cmd_load),
        .cmd_host_addr  (cmd_host_addr),
        .cmd_slot_id    (cmd_slot_id),
        .cmd_byte_count (cmd_byte_count),
        .done           (done),
        .error          (error),
        .bytes_moved    (bytes_moved),
        .bus_req        (bus_req),
        .bus_addr       (bus_addr),
        .bus_wen        (bus_wen),
        .bus_wdata      (bus_wdata),
        .bus_rdata      (bus_rdata),
        .bus_ack        (bus_ack),
        .scratch_req    (scratch_req),
        .scratch_addr   (scratch_addr),
        .scratch_wen    (scratch_wen),
        .scratch_wdata  (scratch_wdata),
        .scratch_grant  (scratch_grant),
        .scratch_rdata  (scratch_rdata)
    );

    dma_engine_props props (
        .clk            (clk),
        .rst_n          (rst_n),
        .cmd_valid      (cmd_valid),
        .cmd_ready      (cmd_ready),
        .cmd_slot_id    (cmd_slot_id),
        .cmd_byte_count (cmd_byte_count),
        .done           (done),
        .error          (error),
        .scratch_req    (scratch_req),
        .bus_req        (bus_req)
    );

    logic _unused;
    assign _unused = &{1'b0, bytes_moved, bus_addr, bus_wen, bus_wdata,
                       scratch_addr, scratch_wen, scratch_wdata};
endmodule
