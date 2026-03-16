module tile_scheduler_formal;
    localparam FORMAL_NUM_SLOTS = 4;
    localparam FORMAL_SLOT_BITS = 2;
    localparam FORMAL_SLOT_STATE_W = FORMAL_NUM_SLOTS * 2;

    (* gclk *) logic clk;

    logic rst_n;
    logic f_past_valid;

    logic        enable;
    (* anyseq *) logic        action_valid;
    (* anyseq *) logic [2:0]  action_type;
    (* anyseq *) logic        action_load;
    (* anyseq *) logic [FORMAL_SLOT_BITS-1:0] action_src_slot;
    (* anyseq *) logic [FORMAL_SLOT_BITS-1:0] action_dst_slot;
    (* anyseq *) logic [7:0]  action_dim_m;
    (* anyseq *) logic [7:0]  action_dim_n;
    (* anyseq *) logic [7:0]  action_dim_k;
    (* anyseq *) logic [7:0]  action_flags;
    (* anyseq *) logic [31:0] action_host_addr;

    logic        action_ready;
    logic        dma_cmd_valid;
    logic        dma_cmd_ready;
    logic        dma_cmd_load;
    logic [31:0] dma_cmd_host_addr;
    logic [FORMAL_SLOT_BITS-1:0] dma_cmd_slot_id;
    logic [12:0] dma_cmd_byte_count;
    logic        dma_done;
    logic        dma_error;
    logic        compute_cmd_valid;
    logic        compute_cmd_ready;
    logic [FORMAL_SLOT_BITS-1:0] compute_src_slot;
    logic [FORMAL_SLOT_BITS-1:0] compute_src2_slot;
    logic [FORMAL_SLOT_BITS-1:0] compute_dst_slot;
    logic [7:0]  compute_dim_m;
    logic [7:0]  compute_dim_n;
    logic [7:0]  compute_dim_k;
    logic        compute_accum;
    logic        compute_saturate;
    logic [3:0]  compute_shift;
    logic        compute_done;
    logic        vector_cmd_valid;
    logic        vector_cmd_ready;
    logic [FORMAL_SLOT_BITS-1:0] vector_src_slot;
    logic [FORMAL_SLOT_BITS-1:0] vector_dst_slot;
    logic [7:0]  vector_rows;
    logic [7:0]  vector_cols;
    logic        vector_approx;
    logic        vector_done;
    logic        busy;
    logic [63:0] dut_slot_state_out;
    logic [63:0] slot_state_out;
    logic        perf_busy_inc;
    logic        perf_stall_inc;
    logic        perf_tile_inc;

    initial f_past_valid = 1'b0;

    always_ff @(posedge clk) begin
        f_past_valid <= 1'b1;
        dma_done <= dma_cmd_valid;
        compute_done <= compute_cmd_valid;
        vector_done <= vector_cmd_valid;

        if (f_past_valid && $past(rst_n) && $past(action_valid && !action_ready)) begin
            assume(action_valid);
            assume(action_type == $past(action_type));
            assume(action_load == $past(action_load));
            assume(action_src_slot == $past(action_src_slot));
            assume(action_dst_slot == $past(action_dst_slot));
            assume(action_dim_m == $past(action_dim_m));
            assume(action_dim_n == $past(action_dim_n));
            assume(action_dim_k == $past(action_dim_k));
            assume(action_flags == $past(action_flags));
            assume(action_host_addr == $past(action_host_addr));
        end

        if (action_valid)
            assume(action_type <= 3'd5);
    end

    assign rst_n = f_past_valid;
    assign enable = 1'b1;
    assign dma_cmd_ready = 1'b1;
    assign compute_cmd_ready = 1'b1;
    assign vector_cmd_ready = 1'b1;
    assign dma_error = 1'b0;
    assign slot_state_out = {
        {(64-FORMAL_SLOT_STATE_W){1'b0}},
        dut_slot_state_out[FORMAL_SLOT_STATE_W-1:0]
    };

    tile_scheduler #(
        .NUM_SLOTS(FORMAL_NUM_SLOTS),
        .SLOT_BITS(FORMAL_SLOT_BITS)
    ) dut (
        .clk               (clk),
        .rst_n             (rst_n),
        .enable            (enable),
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
        .action_host_addr  (action_host_addr),
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
        .busy              (busy),
        .slot_state_out    (dut_slot_state_out),
        .perf_busy_inc     (perf_busy_inc),
        .perf_stall_inc    (perf_stall_inc),
        .perf_tile_inc     (perf_tile_inc)
    );

    tile_scheduler_props #(
        .NUM_SLOTS(FORMAL_NUM_SLOTS),
        .SLOT_BITS(FORMAL_SLOT_BITS)
    ) props (
        .clk             (clk),
        .rst_n           (rst_n),
        .enable          (enable),
        .action_valid    (action_valid),
        .action_ready    (action_ready),
        .action_type     (action_type),
        .action_load     (action_load),
        .busy            (busy),
        .slot_state_out  (slot_state_out),
        .dma_cmd_valid   (dma_cmd_valid),
        .dma_cmd_load    (dma_cmd_load),
        .dma_cmd_slot_id (dma_cmd_slot_id),
        .compute_cmd_valid(compute_cmd_valid),
        .compute_src_slot(compute_src_slot),
        .compute_dst_slot(compute_dst_slot),
        .vector_cmd_valid(vector_cmd_valid),
        .vector_src_slot (vector_src_slot),
        .vector_dst_slot (vector_dst_slot),
        .dma_done        (dma_done),
        .compute_done    (compute_done),
        .vector_done     (vector_done)
    );

endmodule
