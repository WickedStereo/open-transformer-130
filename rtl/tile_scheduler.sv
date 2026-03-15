module tile_scheduler #(
    parameter NUM_SLOTS = 32,
    parameter SLOT_BITS = 5
) (
    input  logic                     clk,
    input  logic                     rst_n,
    input  logic                     enable,

    // Action from decoder
    input  logic                     action_valid,
    output logic                     action_ready,
    input  logic [2:0]               action_type,
    input  logic                     action_load,
    input  logic [SLOT_BITS-1:0]     action_src_slot,
    input  logic [SLOT_BITS-1:0]     action_dst_slot,
    input  logic [7:0]               action_dim_m,
    input  logic [7:0]               action_dim_n,
    input  logic [7:0]               action_dim_k,
    input  logic [7:0]               action_flags,
    input  logic [31:0]              action_host_addr,

    // DMA command interface
    output logic                     dma_cmd_valid,
    input  logic                     dma_cmd_ready,
    output logic                     dma_cmd_load,
    output logic [31:0]              dma_cmd_host_addr,
    output logic [SLOT_BITS-1:0]     dma_cmd_slot_id,
    output logic [12:0]              dma_cmd_byte_count,
    input  logic                     dma_done,
    input  logic                     dma_error,

    // MAC array command interface
    output logic                     compute_cmd_valid,
    input  logic                     compute_cmd_ready,
    output logic [SLOT_BITS-1:0]     compute_src_slot,
    output logic [SLOT_BITS-1:0]     compute_src2_slot,
    output logic [SLOT_BITS-1:0]     compute_dst_slot,
    output logic [7:0]               compute_dim_m,
    output logic [7:0]               compute_dim_n,
    output logic [7:0]               compute_dim_k,
    output logic                     compute_accum,
    output logic                     compute_saturate,
    output logic [3:0]               compute_shift,
    input  logic                     compute_done,

    // Vector/softmax command interface
    output logic                     vector_cmd_valid,
    input  logic                     vector_cmd_ready,
    output logic [SLOT_BITS-1:0]     vector_src_slot,
    output logic [SLOT_BITS-1:0]     vector_dst_slot,
    output logic [7:0]               vector_rows,
    output logic [7:0]               vector_cols,
    output logic                     vector_approx,
    input  logic                     vector_done,

    // Status
    output logic                     busy,
    output logic [63:0]              slot_state_out,

    // Performance counters (active-high increment pulses)
    output logic                     perf_busy_inc,
    output logic                     perf_stall_inc,
    output logic                     perf_tile_inc
);

    // ── Slot residency tracking ──
    // 2 bits per slot: 00=FREE, 01=LOADING, 10=RESIDENT, 11=STORING
    localparam SLOT_FREE     = 2'b00;
    localparam SLOT_LOADING  = 2'b01;
    localparam SLOT_RESIDENT = 2'b10;
    localparam SLOT_STORING  = 2'b11;

    logic [1:0] slot_state [NUM_SLOTS];
    integer slot_idx_comb;
    integer slot_idx_ff;

    // Pack slot_state into flat output
    genvar si;
    generate
        for (si = 0; si < NUM_SLOTS; si++) begin : gen_slot_pack
            assign slot_state_out[si*2 +: 2] = slot_state[si];
        end
    endgenerate

    // ── Action types (matching decoder output encoding) ──
    localparam ACT_NOP     = 3'd0;
    localparam ACT_DMA     = 3'd1;
    localparam ACT_COMPUTE = 3'd2;
    localparam ACT_VECTOR  = 3'd3;
    localparam ACT_CONFIG  = 3'd4;
    localparam ACT_BARRIER = 3'd5;

    // ── FSM ──
    localparam ST_IDLE          = 4'd0;
    localparam ST_DECODE        = 4'd1;
    localparam ST_ISSUE_DMA     = 4'd2;
    localparam ST_WAIT_DMA      = 4'd3;
    localparam ST_ISSUE_COMPUTE = 4'd4;
    localparam ST_WAIT_COMPUTE  = 4'd5;
    localparam ST_ISSUE_VECTOR  = 4'd6;
    localparam ST_WAIT_VECTOR   = 4'd7;
    localparam ST_BARRIER_WAIT  = 4'd8;
    localparam ST_CONFIG_WRITE  = 4'd9;

    logic [3:0] sched_state;

    // Latched action fields
    logic [2:0]          act_type_r;
    logic                act_load_r;
    logic [SLOT_BITS-1:0] act_src_r, act_dst_r;
    logic [7:0]          act_m_r, act_n_r, act_k_r;
    logic [7:0]          act_flags_r;
    logic [31:0]         act_host_addr_r;

    // Helpers
    wire src_resident = (slot_state[act_src_r] == SLOT_RESIDENT);
    wire dst_resident = (slot_state[act_dst_r] == SLOT_RESIDENT);

    // Check if any slot is in a non-idle state (for BARRIER)
    logic any_inflight;
    always_comb begin
        any_inflight = 1'b0;
        for (slot_idx_comb = 0; slot_idx_comb < NUM_SLOTS; slot_idx_comb = slot_idx_comb + 1) begin
            if (slot_state[slot_idx_comb] == SLOT_LOADING ||
                slot_state[slot_idx_comb] == SLOT_STORING)
                any_inflight = 1'b1;
        end
    end

    // ── Output defaults ──
    assign action_ready = (sched_state == ST_IDLE) && enable;
    assign busy = (sched_state != ST_IDLE);

    // Performance counter pulses
    assign perf_busy_inc  = (sched_state != ST_IDLE);
    assign perf_stall_inc = (sched_state == ST_WAIT_DMA) ||
                            (sched_state == ST_WAIT_COMPUTE) ||
                            (sched_state == ST_WAIT_VECTOR) ||
                            (sched_state == ST_BARRIER_WAIT);
    assign perf_tile_inc  = compute_done || vector_done;

    // DMA command outputs
    assign dma_cmd_valid      = (sched_state == ST_ISSUE_DMA);
    assign dma_cmd_load       = act_load_r;
    assign dma_cmd_slot_id    = act_load_r ? act_dst_r : act_src_r;
    assign dma_cmd_host_addr  = act_host_addr_r +
                                ({27'd0, (act_load_r ? act_dst_r : act_src_r)} << 12);
    assign dma_cmd_byte_count = {5'b0, act_m_r} * {5'b0, act_n_r};

    // Compute command outputs
    assign compute_cmd_valid = (sched_state == ST_ISSUE_COMPUTE);
    assign compute_src_slot  = act_src_r;
    assign compute_src2_slot = act_dst_r;  // B-side tile for MATMUL
    assign compute_dst_slot  = act_dst_r;
    assign compute_dim_m     = act_m_r;
    assign compute_dim_n     = act_n_r;
    assign compute_dim_k     = act_k_r;
    assign compute_accum     = act_flags_r[7];
    assign compute_saturate  = act_flags_r[6];
    assign compute_shift     = act_flags_r[3:0];

    // Bits [5:4] of flags are reserved for future use
    logic _unused_flags;
    assign _unused_flags = &{1'b0, act_flags_r[5:4]};

    // Vector command outputs
    assign vector_cmd_valid = (sched_state == ST_ISSUE_VECTOR);
    assign vector_src_slot  = act_src_r;
    assign vector_dst_slot  = act_dst_r;
    assign vector_rows      = act_m_r;
    assign vector_cols      = act_n_r;
    assign vector_approx    = act_flags_r[7];

    // ── Main state machine ──
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            sched_state     <= ST_IDLE;
            act_type_r      <= '0;
            act_load_r      <= 1'b0;
            act_src_r       <= '0;
            act_dst_r       <= '0;
            act_m_r         <= '0;
            act_n_r         <= '0;
            act_k_r         <= '0;
            act_flags_r     <= '0;
            act_host_addr_r <= '0;
            for (slot_idx_ff = 0; slot_idx_ff < NUM_SLOTS; slot_idx_ff = slot_idx_ff + 1)
                slot_state[slot_idx_ff] <= SLOT_FREE;
        end else begin
            case (sched_state)
                ST_IDLE: begin
                    if (action_valid && enable) begin
                        act_type_r      <= action_type;
                        act_load_r      <= action_load;
                        act_src_r       <= action_src_slot;
                        act_dst_r       <= action_dst_slot;
                        act_m_r         <= action_dim_m;
                        act_n_r         <= action_dim_n;
                        act_k_r         <= action_dim_k;
                        act_flags_r     <= action_flags;
                        act_host_addr_r <= action_host_addr;
                        sched_state     <= ST_DECODE;
                    end
                end

                ST_DECODE: begin
                    case (act_type_r)
                        ACT_NOP:     sched_state <= ST_IDLE;
                        ACT_DMA:     sched_state <= ST_ISSUE_DMA;
                        ACT_COMPUTE: begin
                            if (src_resident && dst_resident)
                                sched_state <= ST_ISSUE_COMPUTE;
                            // else stay in DECODE waiting for operands
                        end
                        ACT_VECTOR:  begin
                            if (src_resident)
                                sched_state <= ST_ISSUE_VECTOR;
                        end
                        ACT_CONFIG:  sched_state <= ST_CONFIG_WRITE;
                        ACT_BARRIER: sched_state <= ST_BARRIER_WAIT;
                        default:     sched_state <= ST_IDLE;
                    endcase
                end

                ST_ISSUE_DMA: begin
                    if (dma_cmd_ready) begin
                        if (act_load_r)
                            slot_state[act_dst_r] <= SLOT_LOADING;
                        else
                            slot_state[act_src_r] <= SLOT_STORING;
                        sched_state <= ST_WAIT_DMA;
                    end
                end

                ST_WAIT_DMA: begin
                    if (dma_done) begin
                        if (act_load_r)
                            slot_state[act_dst_r] <= SLOT_RESIDENT;
                        else
                            slot_state[act_src_r] <= SLOT_FREE;
                        sched_state <= ST_IDLE;
                    end else if (dma_error) begin
                        if (act_load_r)
                            slot_state[act_dst_r] <= SLOT_FREE;
                        else
                            slot_state[act_src_r] <= SLOT_RESIDENT;
                        sched_state <= ST_IDLE;
                    end
                end

                ST_ISSUE_COMPUTE: begin
                    if (compute_cmd_ready)
                        sched_state <= ST_WAIT_COMPUTE;
                end

                ST_WAIT_COMPUTE: begin
                    if (compute_done)
                        sched_state <= ST_IDLE;
                end

                ST_ISSUE_VECTOR: begin
                    if (vector_cmd_ready)
                        sched_state <= ST_WAIT_VECTOR;
                end

                ST_WAIT_VECTOR: begin
                    if (vector_done)
                        sched_state <= ST_IDLE;
                end

                ST_BARRIER_WAIT: begin
                    if (!any_inflight)
                        sched_state <= ST_IDLE;
                end

                ST_CONFIG_WRITE: begin
                    sched_state <= ST_IDLE;
                end

                default: sched_state <= ST_IDLE;
            endcase
        end
    end

endmodule
