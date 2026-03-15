module attn_core #(
    parameter NUM_BANKS     = 8,
    parameter BANK_SIZE     = 16384,
    parameter BANK_ADDR_W   = 14,
    parameter DATA_W        = 8,
    parameter SLOT_BITS     = 5
) (
    input  logic        clk,
    input  logic        rst_n,

    // Host MMIO port
    input  logic [5:0]  mmio_addr,
    input  logic        mmio_wen,
    input  logic [31:0] mmio_wdata,
    output logic [31:0] mmio_rdata,
    input  logic        mmio_valid,
    output logic        mmio_ready,

    // Host bus for DMA and queue fetch
    output logic        bus_req,
    output logic [31:0] bus_addr,
    output logic        bus_wen,
    output logic [127:0] bus_wdata,
    input  logic [127:0] bus_rdata,
    input  logic        bus_ack,

    // Queue fetch bus (separate from DMA for simplicity)
    output logic        qbus_req,
    output logic [31:0] qbus_addr,
    input  logic [63:0] qbus_rdata,
    input  logic        qbus_ack
);

    // ── MMIO outputs ──
    logic        ctrl_enable, ctrl_soft_reset, ctrl_fault_clear;
    logic [31:0] queue_base;
    logic [3:0]  queue_size_log2;
    logic [7:0]  cmd_head;
    logic [7:0]  tile_default_m, tile_default_n, tile_default_k;
    logic [31:0] dma_host_addr_cfg, scratch_base_cfg;

    // Status inputs to MMIO
    logic [7:0]  cmd_tail;
    logic        status_busy, status_fault, status_dma_active, status_compute_active;
    logic [3:0]  status_queue_depth;
    logic [63:0] fault_info_desc;
    logic [7:0]  fault_info_opcode;
    logic [1:0]  fault_info_cause;
    logic [31:0] perf_busy_cycles, perf_stall_cycles, perf_dma_bytes, perf_tile_count;

    mmio_regs u_mmio (
        .clk                 (clk),
        .rst_n               (rst_n),
        .mmio_addr           (mmio_addr),
        .mmio_wen            (mmio_wen),
        .mmio_wdata          (mmio_wdata),
        .mmio_rdata          (mmio_rdata),
        .mmio_valid          (mmio_valid),
        .mmio_ready          (mmio_ready),
        .ctrl_enable         (ctrl_enable),
        .ctrl_soft_reset     (ctrl_soft_reset),
        .ctrl_fault_clear    (ctrl_fault_clear),
        .queue_base          (queue_base),
        .queue_size_log2     (queue_size_log2),
        .cmd_head            (cmd_head),
        .tile_default_m      (tile_default_m),
        .tile_default_n      (tile_default_n),
        .tile_default_k      (tile_default_k),
        .dma_host_addr       (dma_host_addr_cfg),
        .scratch_base        (scratch_base_cfg),
        .cmd_tail            (cmd_tail),
        .status_busy         (status_busy),
        .status_fault        (status_fault),
        .status_dma_active   (status_dma_active),
        .status_compute_active (status_compute_active),
        .status_queue_depth  (status_queue_depth),
        .fault_info_desc     (fault_info_desc),
        .fault_info_opcode   (fault_info_opcode),
        .fault_info_cause    (fault_info_cause),
        .perf_busy_cycles    (perf_busy_cycles),
        .perf_stall_cycles   (perf_stall_cycles),
        .perf_dma_bytes      (perf_dma_bytes),
        .perf_tile_count     (perf_tile_count)
    );

    // ── Queue controller ──
    logic        desc_valid, desc_consumed;
    logic [63:0] desc_data;

    queue_ctrl u_queue (
        .clk             (clk),
        .rst_n           (rst_n),
        .queue_base      (queue_base),
        .queue_size_log2 (queue_size_log2),
        .head            (cmd_head),
        .tail            (cmd_tail),
        .fault_halt      (status_fault),
        .enable          (ctrl_enable),
        .desc_valid      (desc_valid),
        .desc_data       (desc_data),
        .desc_consumed   (desc_consumed),
        .bus_req         (qbus_req),
        .bus_addr        (qbus_addr),
        .bus_rdata       (qbus_rdata),
        .bus_ack         (qbus_ack)
    );

    // Queue depth
    assign status_queue_depth = cmd_head[3:0] - cmd_tail[3:0];

    // ── Decoder ──
    logic        action_valid, action_ready;
    logic [2:0]  action_type;
    logic        action_load;
    logic [4:0]  action_src_slot, action_dst_slot;
    logic [7:0]  action_dim_m, action_dim_n, action_dim_k;
    logic [7:0]  action_flags;
    logic [3:0]  action_tag;
    logic        fault_valid, fault_active;

    isa_decoder u_decoder (
        .clk              (clk),
        .rst_n            (rst_n),
        .desc_valid       (desc_valid),
        .desc_data        (desc_data),
        .desc_consumed    (desc_consumed),
        .default_m        (tile_default_m),
        .default_n        (tile_default_n),
        .default_k        (tile_default_k),
        .action_valid     (action_valid),
        .action_ready     (action_ready),
        .action_type      (action_type),
        .action_load      (action_load),
        .action_src_slot  (action_src_slot),
        .action_dst_slot  (action_dst_slot),
        .action_dim_m     (action_dim_m),
        .action_dim_n     (action_dim_n),
        .action_dim_k     (action_dim_k),
        .action_flags     (action_flags),
        .action_tag       (action_tag),
        .fault_valid      (fault_valid),
        .fault_cause      (fault_info_cause),
        .fault_descriptor (fault_info_desc),
        .fault_clear      (ctrl_fault_clear),
        .fault_active     (fault_active)
    );

    assign status_fault     = fault_active;
    assign fault_info_opcode = fault_info_desc[63:56];

    // ── Tile scheduler ──
    logic        dma_cmd_valid, dma_cmd_ready, dma_cmd_load;
    logic [31:0] dma_cmd_host_addr;
    logic [4:0]  dma_cmd_slot_id;
    logic [12:0] dma_cmd_byte_count;
    logic        dma_done, dma_error;

    logic        compute_cmd_valid, compute_cmd_ready;
    logic [4:0]  compute_src_slot, compute_src2_slot, compute_dst_slot;
    logic [7:0]  compute_dim_m, compute_dim_n, compute_dim_k;
    logic        compute_accum, compute_saturate;
    logic [3:0]  compute_shift;
    logic        compute_done;

    logic        vector_cmd_valid, vector_cmd_ready;
    logic [4:0]  vector_src_slot, vector_dst_slot;
    logic [7:0]  vector_rows, vector_cols;
    logic        vector_approx;
    logic        vector_done;

    logic [63:0] slot_state_out;
    logic        perf_busy_inc, perf_stall_inc, perf_tile_inc;

    tile_scheduler u_scheduler (
        .clk               (clk),
        .rst_n             (rst_n),
        .enable            (ctrl_enable),
        .action_valid      (action_valid),
        .action_ready      (action_ready),
        .action_type       (action_type),
        .action_load       (action_load),
        .action_src_slot   (action_src_slot),
        .action_dst_slot   (action_dst_slot),
        .action_dim_m      (action_dim_m),
        .action_dim_n      (action_dim_n),
        .action_dim_k      (action_dim_k),
        .action_flags      (action_flags),
        .action_host_addr  (dma_host_addr_cfg),
        .dma_cmd_valid     (dma_cmd_valid),
        .dma_cmd_ready     (dma_cmd_ready),
        .dma_cmd_load      (dma_cmd_load),
        .dma_cmd_host_addr (dma_cmd_host_addr),
        .dma_cmd_slot_id   (dma_cmd_slot_id),
        .dma_cmd_byte_count(dma_cmd_byte_count),
        .dma_done          (dma_done),
        .dma_error         (dma_error),
        .compute_cmd_valid (compute_cmd_valid),
        .compute_cmd_ready (compute_cmd_ready),
        .compute_src_slot  (compute_src_slot),
        .compute_src2_slot (compute_src2_slot),
        .compute_dst_slot  (compute_dst_slot),
        .compute_dim_m     (compute_dim_m),
        .compute_dim_n     (compute_dim_n),
        .compute_dim_k     (compute_dim_k),
        .compute_accum     (compute_accum),
        .compute_saturate  (compute_saturate),
        .compute_shift     (compute_shift),
        .compute_done      (compute_done),
        .vector_cmd_valid  (vector_cmd_valid),
        .vector_cmd_ready  (vector_cmd_ready),
        .vector_src_slot   (vector_src_slot),
        .vector_dst_slot   (vector_dst_slot),
        .vector_rows       (vector_rows),
        .vector_cols       (vector_cols),
        .vector_approx     (vector_approx),
        .vector_done       (vector_done),
        .busy              (status_busy),
        .slot_state_out    (slot_state_out),
        .perf_busy_inc     (perf_busy_inc),
        .perf_stall_inc    (perf_stall_inc),
        .perf_tile_inc     (perf_tile_inc)
    );

    // ── DMA engine ──
    logic [NUM_BANKS-1:0]              dma_scratch_req;
    logic [NUM_BANKS*BANK_ADDR_W-1:0]  dma_scratch_addr;
    logic [NUM_BANKS-1:0]              dma_scratch_wen;
    logic [NUM_BANKS*DATA_W-1:0]       dma_scratch_wdata;
    logic [NUM_BANKS-1:0]              dma_scratch_grant;
    logic [NUM_BANKS*DATA_W-1:0]       dma_scratch_rdata;
    logic [31:0]                       dma_bytes_moved;

    dma_engine #(
        .NUM_BANKS   (NUM_BANKS),
        .BANK_ADDR_W (BANK_ADDR_W),
        .DATA_W      (DATA_W),
        .SLOT_BITS   (SLOT_BITS)
    ) u_dma (
        .clk            (clk),
        .rst_n          (rst_n),
        .cmd_valid      (dma_cmd_valid),
        .cmd_ready      (dma_cmd_ready),
        .cmd_load       (dma_cmd_load),
        .cmd_host_addr  (dma_cmd_host_addr),
        .cmd_slot_id    (dma_cmd_slot_id),
        .cmd_byte_count (dma_cmd_byte_count),
        .done           (dma_done),
        .error          (dma_error),
        .bytes_moved    (dma_bytes_moved),
        .bus_req        (bus_req),
        .bus_addr       (bus_addr),
        .bus_wen        (bus_wen),
        .bus_wdata      (bus_wdata),
        .bus_rdata      (bus_rdata),
        .bus_ack        (bus_ack),
        .scratch_req    (dma_scratch_req),
        .scratch_addr   (dma_scratch_addr),
        .scratch_wen    (dma_scratch_wen),
        .scratch_wdata  (dma_scratch_wdata),
        .scratch_grant  (dma_scratch_grant),
        .scratch_rdata  (dma_scratch_rdata)
    );

    assign status_dma_active = !dma_cmd_ready;

    // ── Compute engine ──
    logic [NUM_BANKS-1:0]              mac_scratch_req;
    logic [NUM_BANKS*BANK_ADDR_W-1:0]  mac_scratch_addr;
    logic [NUM_BANKS-1:0]              mac_scratch_wen;
    logic [NUM_BANKS*DATA_W-1:0]       mac_scratch_wdata;
    logic [NUM_BANKS-1:0]              mac_scratch_grant;
    logic [NUM_BANKS*DATA_W-1:0]       mac_scratch_rdata;
    logic                              compute_busy;

    compute_engine #(
        .NUM_BANKS   (NUM_BANKS),
        .BANK_ADDR_W (BANK_ADDR_W),
        .DATA_W      (DATA_W),
        .SLOT_BITS   (SLOT_BITS)
    ) u_compute (
        .clk           (clk),
        .rst_n         (rst_n),
        .cmd_valid     (compute_cmd_valid),
        .cmd_ready     (compute_cmd_ready),
        .cmd_src_slot  (compute_src_slot),
        .cmd_src2_slot (compute_src2_slot),
        .cmd_dst_slot  (compute_dst_slot),
        .cmd_dim_m     (compute_dim_m),
        .cmd_dim_n     (compute_dim_n),
        .cmd_dim_k     (compute_dim_k),
        .cmd_accum     (compute_accum),
        .cmd_saturate  (compute_saturate),
        .cmd_shift     (compute_shift),
        .done          (compute_done),
        .busy          (compute_busy),
        .scratch_req   (mac_scratch_req),
        .scratch_addr  (mac_scratch_addr),
        .scratch_wen   (mac_scratch_wen),
        .scratch_wdata (mac_scratch_wdata),
        .scratch_grant (mac_scratch_grant),
        .scratch_rdata (mac_scratch_rdata)
    );

    assign status_compute_active = compute_busy;

    // ── Vector unit ──
    logic [NUM_BANKS-1:0]              vec_scratch_req;
    logic [NUM_BANKS*BANK_ADDR_W-1:0]  vec_scratch_addr;
    logic [NUM_BANKS-1:0]              vec_scratch_wen;
    logic [NUM_BANKS*DATA_W-1:0]       vec_scratch_wdata;
    logic [NUM_BANKS-1:0]              vec_scratch_grant;
    logic [NUM_BANKS*DATA_W-1:0]       vec_scratch_rdata;
    logic                              vec_busy;

    vector_unit #(
        .NUM_BANKS   (NUM_BANKS),
        .BANK_ADDR_W (BANK_ADDR_W),
        .DATA_W      (DATA_W),
        .SLOT_BITS   (SLOT_BITS)
    ) u_vector (
        .clk          (clk),
        .rst_n        (rst_n),
        .cmd_valid    (vector_cmd_valid),
        .cmd_ready    (vector_cmd_ready),
        .cmd_src_slot (vector_src_slot),
        .cmd_dst_slot (vector_dst_slot),
        .cmd_rows     (vector_rows),
        .cmd_cols     (vector_cols),
        .cmd_approx   (vector_approx),
        .done         (vector_done),
        .busy         (vec_busy),
        .scratch_req  (vec_scratch_req),
        .scratch_addr (vec_scratch_addr),
        .scratch_wen  (vec_scratch_wen),
        .scratch_wdata(vec_scratch_wdata),
        .scratch_grant(vec_scratch_grant),
        .scratch_rdata(vec_scratch_rdata)
    );

    // ── Bank arbiter ──
    logic [NUM_BANKS-1:0]              bank_en;
    logic [NUM_BANKS-1:0]              bank_wen;
    logic [NUM_BANKS*BANK_ADDR_W-1:0]  bank_addr;
    logic [NUM_BANKS*DATA_W-1:0]       bank_wdata;
    logic [NUM_BANKS*DATA_W-1:0]       bank_rdata;
    logic [NUM_BANKS-1:0]              arb_conflict;

    bank_arbiter #(
        .NUM_BANKS (NUM_BANKS),
        .ADDR_W    (BANK_ADDR_W),
        .DATA_W    (DATA_W)
    ) u_arbiter (
        .clk          (clk),
        .rst_n        (rst_n),
        .dma_req      (dma_scratch_req),
        .dma_addr     (dma_scratch_addr),
        .dma_wen      (dma_scratch_wen),
        .dma_wdata    (dma_scratch_wdata),
        .dma_grant    (dma_scratch_grant),
        .dma_rdata    (dma_scratch_rdata),
        .mac_req      (mac_scratch_req),
        .mac_addr     (mac_scratch_addr),
        .mac_wen      (mac_scratch_wen),
        .mac_wdata    (mac_scratch_wdata),
        .mac_grant    (mac_scratch_grant),
        .mac_rdata    (mac_scratch_rdata),
        .vec_req      (vec_scratch_req),
        .vec_addr     (vec_scratch_addr),
        .vec_wen      (vec_scratch_wen),
        .vec_wdata    (vec_scratch_wdata),
        .vec_grant    (vec_scratch_grant),
        .vec_rdata    (vec_scratch_rdata),
        .bank_en      (bank_en),
        .bank_wen_o   (bank_wen),
        .bank_addr_o  (bank_addr),
        .bank_wdata_o (bank_wdata),
        .bank_rdata_i (bank_rdata),
        .arb_conflict (arb_conflict)
    );

    // ── Scratchpad ──
    scratchpad #(
        .NUM_BANKS   (NUM_BANKS),
        .BANK_SIZE   (BANK_SIZE),
        .BANK_ADDR_W (BANK_ADDR_W),
        .DATA_W      (DATA_W)
    ) u_scratchpad (
        .clk        (clk),
        .rst_n      (rst_n),
        .bank_en    (bank_en),
        .bank_wen   (bank_wen),
        .bank_addr  (bank_addr),
        .bank_wdata (bank_wdata),
        .bank_rdata (bank_rdata)
    );

    // ── Performance counters ──
    perf_counters u_perf (
        .clk             (clk),
        .rst_n           (rst_n),
        .soft_reset      (ctrl_soft_reset),
        .busy_inc        (perf_busy_inc),
        .stall_inc       (perf_stall_inc),
        .dma_bytes_inc   (dma_bytes_moved),
        .dma_bytes_valid (dma_done),
        .tile_inc        (perf_tile_inc),
        .busy_cycles     (perf_busy_cycles),
        .stall_cycles    (perf_stall_cycles),
        .dma_bytes       (perf_dma_bytes),
        .tile_count      (perf_tile_count)
    );

    // Suppress warnings for unused integration signals
    logic _unused;
    assign _unused = &{1'b0, slot_state_out, arb_conflict, action_tag,
                       fault_valid, dma_bytes_moved, vec_busy,
                       compute_src_slot, compute_src2_slot, compute_dst_slot,
                       compute_dim_m, compute_dim_n, compute_dim_k,
                       compute_accum, compute_saturate, compute_shift,
                       mac_scratch_grant, mac_scratch_rdata,
                       scratch_base_cfg};

endmodule
