module compute_engine #(
    parameter NUM_BANKS      = 8,
    parameter BANK_ADDR_W    = 14,
    parameter DATA_W         = 8,
    parameter SLOT_BITS      = 5,
    parameter NUM_LANES      = 16,
    parameter MAX_TILE_BYTES = 4096
) (
    input  logic                              clk,
    input  logic                              rst_n,

    // Command interface (from scheduler)
    input  logic                              cmd_valid,
    output logic                              cmd_ready,
    input  logic [SLOT_BITS-1:0]              cmd_src_slot,
    input  logic [SLOT_BITS-1:0]              cmd_src2_slot,
    input  logic [SLOT_BITS-1:0]              cmd_dst_slot,
    input  logic [7:0]                        cmd_dim_m,
    input  logic [7:0]                        cmd_dim_n,
    input  logic [7:0]                        cmd_dim_k,
    input  logic                              cmd_accum,
    input  logic                              cmd_saturate,
    input  logic [3:0]                        cmd_shift,

    // Completion / status
    output logic                              done,
    output logic                              busy,

    // Scratchpad bank arbiter (packed)
    output logic [NUM_BANKS-1:0]              scratch_req,
    output logic [NUM_BANKS*BANK_ADDR_W-1:0]  scratch_addr,
    output logic [NUM_BANKS-1:0]              scratch_wen,
    output logic [NUM_BANKS*DATA_W-1:0]       scratch_wdata,
    input  logic [NUM_BANKS-1:0]              scratch_grant,
    input  logic [NUM_BANKS*DATA_W-1:0]       scratch_rdata
);

    localparam ST_IDLE         = 4'd0;
    localparam ST_READ_A_REQ   = 4'd1;
    localparam ST_READ_A_DATA  = 4'd2;
    localparam ST_READ_B_REQ   = 4'd3;
    localparam ST_READ_B_DATA  = 4'd4;
    localparam ST_ISSUE_TILE   = 4'd5;
    localparam ST_FEED_MAC     = 4'd6;
    localparam ST_WAIT_RESULT  = 4'd7;
    localparam ST_WRITE_REQ    = 4'd8;
    localparam ST_DONE         = 4'd9;
    localparam integer LOCAL_ADDR_W = 17;
    localparam integer BANK_BITS = (NUM_BANKS > 1) ? $clog2(NUM_BANKS) : 1;
    localparam integer SLOT_ADDR_W = BANK_ADDR_W + BANK_BITS - SLOT_BITS;
    localparam [LOCAL_ADDR_W-1:0] GROUP_STRIDE = NUM_LANES;

    logic [3:0] state;

    logic [SLOT_BITS-1:0] src_slot_r, src2_slot_r, dst_slot_r;
    logic [7:0]           dim_m_r, dim_n_r, dim_k_r;
    logic                 saturate_r;
    logic [3:0]           shift_r;

    logic [15:0] a_total_bytes_r, b_total_bytes_r;
    logic [15:0] prefetch_idx;
    logic [7:0]  row_idx, group_idx, k_idx;
    logic [4:0]  write_idx;
    logic [BANK_BITS-1:0] read_bank_r;

    logic [7:0] a_buf [0:MAX_TILE_BYTES-1];
    logic [7:0] b_buf [0:MAX_TILE_BYTES-1];
    logic [7:0] write_buf [0:NUM_LANES-1];

    logic [NUM_LANES*DATA_W-1:0]  mac_a_data;
    logic [NUM_LANES*DATA_W-1:0]  mac_b_data;
    logic                         mac_tile_valid, mac_tile_ready;
    logic                         mac_a_valid, mac_b_valid;
    logic                         mac_result_valid, mac_result_ready;
    logic [NUM_LANES*32-1:0]      mac_result_data;
    logic                         mac_busy;

    logic [LOCAL_ADDR_W-1:0] src_base, src2_base, dst_base;
    assign src_base  = {
        {(LOCAL_ADDR_W - SLOT_BITS - SLOT_ADDR_W){1'b0}},
        src_slot_r,
        {SLOT_ADDR_W{1'b0}}
    };
    assign src2_base = {
        {(LOCAL_ADDR_W - SLOT_BITS - SLOT_ADDR_W){1'b0}},
        src2_slot_r,
        {SLOT_ADDR_W{1'b0}}
    };
    assign dst_base  = {
        {(LOCAL_ADDR_W - SLOT_BITS - SLOT_ADDR_W){1'b0}},
        dst_slot_r,
        {SLOT_ADDR_W{1'b0}}
    };

    function automatic [4:0] group_width_for(
        input logic [7:0] dim_n,
        input logic [7:0] group
    );
        integer remaining;
        begin
            remaining = {24'd0, dim_n} - ({24'd0, group} * NUM_LANES);
            if (remaining <= 0)
                group_width_for = 5'd0;
            else if (remaining > NUM_LANES)
                group_width_for = NUM_LANES;
            else
                group_width_for = remaining[4:0];
        end
    endfunction

    function automatic [7:0] num_groups_for(input logic [7:0] dim_n);
        begin
            num_groups_for = (dim_n + NUM_LANES - 1) / NUM_LANES;
        end
    endfunction

    function automatic [7:0] sat_shift_byte(
        input logic signed [31:0] value,
        input logic [3:0]         shift_amt,
        input logic               saturate_en
    );
        logic signed [31:0] shifted;
        begin
            shifted = value >>> shift_amt;
            if (saturate_en) begin
                if (shifted > 32'sd127)
                    sat_shift_byte = 8'd127;
                else if (shifted < -32'sd128)
                    sat_shift_byte = 8'h80;
                else
                    sat_shift_byte = shifted[7:0];
            end else begin
                sat_shift_byte = shifted[7:0];
            end
        end
    endfunction

    logic [LOCAL_ADDR_W-1:0] req_addr;
    logic [LOCAL_ADDR_W-1:0] row_offset;
    logic [LOCAL_ADDR_W-1:0] group_offset;
    logic [BANK_BITS-1:0]    req_bank;
    logic [BANK_ADDR_W-1:0] req_offset;
    logic [7:0]  a_feed_byte;
    integer lane_comb;
    integer lane_reset;
    integer lane_write;

    always_comb begin
        req_addr = '0;
        unique case (state)
            ST_READ_A_REQ: req_addr = src_base + {{(LOCAL_ADDR_W-16){1'b0}}, prefetch_idx};
            ST_READ_B_REQ: req_addr = src2_base + {{(LOCAL_ADDR_W-16){1'b0}}, prefetch_idx};
            ST_WRITE_REQ: req_addr = dst_base + row_offset + group_offset +
                                     {{(LOCAL_ADDR_W-5){1'b0}}, write_idx};
            default: ;
        endcase
    end

    assign req_bank   = req_addr[BANK_ADDR_W + BANK_BITS - 1 -: BANK_BITS];
    assign req_offset = req_addr[BANK_ADDR_W-1:0];
    assign row_offset = {9'b0, row_idx} * {9'b0, dim_n_r};
    assign group_offset = {9'b0, group_idx} * GROUP_STRIDE;
    assign a_feed_byte = a_buf[({8'd0, row_idx} * {8'd0, dim_k_r}) + {8'd0, k_idx}];

    always_comb begin
        scratch_req   = '0;
        scratch_addr  = '0;
        scratch_wen   = '0;
        scratch_wdata = '0;

        if (state == ST_READ_A_REQ || state == ST_READ_B_REQ || state == ST_WRITE_REQ) begin
            scratch_req[req_bank] = 1'b1;
            scratch_addr[req_bank*BANK_ADDR_W +: BANK_ADDR_W] = req_offset;
            if (state == ST_WRITE_REQ) begin
                scratch_wen[req_bank] = 1'b1;
                scratch_wdata[req_bank*DATA_W +: DATA_W] = write_buf[write_idx];
            end
        end
    end

    always_comb begin
        mac_tile_valid   = 1'b0;
        mac_a_valid      = 1'b0;
        mac_b_valid      = 1'b0;
        mac_result_ready = 1'b0;
        mac_a_data       = '0;
        mac_b_data       = '0;

        if (state == ST_ISSUE_TILE) begin
            mac_tile_valid = 1'b1;
        end

        if (state == ST_FEED_MAC) begin
            mac_a_valid = 1'b1;
            mac_b_valid = 1'b1;

            for (lane_comb = 0; lane_comb < NUM_LANES; lane_comb = lane_comb + 1) begin
                mac_a_data[lane_comb*DATA_W +: DATA_W] = a_feed_byte;
                if (lane_comb < group_width_for(dim_n_r, group_idx)) begin
                    mac_b_data[lane_comb*DATA_W +: DATA_W] =
                        b_buf[({8'd0, k_idx} * {8'd0, dim_n_r}) +
                              ({9'b0, group_idx} * GROUP_STRIDE) +
                              lane_comb];
                end
            end
        end

        if (state == ST_WAIT_RESULT) begin
            mac_result_ready = 1'b1;
        end
    end

    mac_array #(
        .NUM_LANES     (NUM_LANES),
        .OPERAND_WIDTH (DATA_W),
        .ACCUM_WIDTH   (32)
    ) u_mac_array (
        .clk         (clk),
        .rst_n       (rst_n),
        .tile_valid  (mac_tile_valid),
        .tile_ready  (mac_tile_ready),
        .tile_m      (8'd1),
        .tile_n      ({3'd0, group_width_for(dim_n_r, group_idx)}),
        .tile_k      (dim_k_r),
        .accum_mode  (1'b0),
        .a_data      (mac_a_data),
        .b_data      (mac_b_data),
        .a_valid     (mac_a_valid),
        .b_valid     (mac_b_valid),
        .result_data (mac_result_data),
        .result_valid(mac_result_valid),
        .result_ready(mac_result_ready),
        .busy        (mac_busy)
    );

    assign cmd_ready = (state == ST_IDLE);
    assign busy      = (state != ST_IDLE);
    assign done      = (state == ST_DONE);

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state          <= ST_IDLE;
            src_slot_r     <= '0;
            src2_slot_r    <= '0;
            dst_slot_r     <= '0;
            dim_m_r        <= '0;
            dim_n_r        <= '0;
            dim_k_r        <= '0;
            saturate_r     <= 1'b0;
            shift_r        <= '0;
            a_total_bytes_r<= '0;
            b_total_bytes_r<= '0;
            prefetch_idx   <= '0;
            row_idx        <= '0;
            group_idx      <= '0;
            k_idx          <= '0;
            write_idx      <= '0;
            read_bank_r    <= '0;
            for (lane_reset = 0; lane_reset < NUM_LANES; lane_reset = lane_reset + 1)
                write_buf[lane_reset] <= '0;
        end else begin
            case (state)
                ST_IDLE: begin
                    if (cmd_valid) begin
                        src_slot_r      <= cmd_src_slot;
                        src2_slot_r     <= cmd_src2_slot;
                        dst_slot_r      <= cmd_dst_slot;
                        dim_m_r         <= cmd_dim_m;
                        dim_n_r         <= cmd_dim_n;
                        dim_k_r         <= cmd_dim_k;
                        saturate_r      <= cmd_saturate;
                        shift_r         <= cmd_shift;
                        a_total_bytes_r <= {8'd0, cmd_dim_m} * {8'd0, cmd_dim_k};
                        b_total_bytes_r <= {8'd0, cmd_dim_k} * {8'd0, cmd_dim_n};
                        prefetch_idx    <= '0;
                        row_idx         <= '0;
                        group_idx       <= '0;
                        k_idx           <= '0;
                        write_idx       <= '0;
                        state           <= ST_READ_A_REQ;
                    end
                end

                ST_READ_A_REQ: begin
                    if (scratch_grant[req_bank]) begin
                        read_bank_r <= req_bank;
                        state       <= ST_READ_A_DATA;
                    end
                end

                ST_READ_A_DATA: begin
                    a_buf[prefetch_idx] <= scratch_rdata[read_bank_r*DATA_W +: DATA_W];
                    if (prefetch_idx + 16'd1 >= a_total_bytes_r) begin
                        prefetch_idx <= '0;
                        state        <= ST_READ_B_REQ;
                    end else begin
                        prefetch_idx <= prefetch_idx + 16'd1;
                        state        <= ST_READ_A_REQ;
                    end
                end

                ST_READ_B_REQ: begin
                    if (scratch_grant[req_bank]) begin
                        read_bank_r <= req_bank;
                        state       <= ST_READ_B_DATA;
                    end
                end

                ST_READ_B_DATA: begin
                    b_buf[prefetch_idx] <= scratch_rdata[read_bank_r*DATA_W +: DATA_W];
                    if (prefetch_idx + 16'd1 >= b_total_bytes_r) begin
                        prefetch_idx <= '0;
                        state        <= ST_ISSUE_TILE;
                    end else begin
                        prefetch_idx <= prefetch_idx + 16'd1;
                        state        <= ST_READ_B_REQ;
                    end
                end

                ST_ISSUE_TILE: begin
                    if (mac_tile_ready) begin
                        k_idx  <= '0;
                        state  <= ST_FEED_MAC;
                    end
                end

                ST_FEED_MAC: begin
                    if (k_idx + 8'd1 >= dim_k_r) begin
                        state <= ST_WAIT_RESULT;
                    end else begin
                        k_idx <= k_idx + 8'd1;
                    end
                end

                ST_WAIT_RESULT: begin
                    if (mac_result_valid) begin
                        for (lane_write = 0; lane_write < NUM_LANES; lane_write = lane_write + 1) begin
                            write_buf[lane_write] <= sat_shift_byte(
                                $signed(mac_result_data[lane_write*32 +: 32]),
                                shift_r,
                                saturate_r
                            );
                        end
                        write_idx <= '0;
                        state     <= ST_WRITE_REQ;
                    end
                end

                ST_WRITE_REQ: begin
                    if (scratch_grant[req_bank]) begin
                        if (write_idx + 5'd1 >= group_width_for(dim_n_r, group_idx)) begin
                            if (group_idx + 8'd1 >= num_groups_for(dim_n_r)) begin
                                if (row_idx + 8'd1 >= dim_m_r) begin
                                    state <= ST_DONE;
                                end else begin
                                    row_idx   <= row_idx + 8'd1;
                                    group_idx <= '0;
                                    k_idx     <= '0;
                                    state     <= ST_ISSUE_TILE;
                                end
                            end else begin
                                group_idx <= group_idx + 8'd1;
                                k_idx     <= '0;
                                state     <= ST_ISSUE_TILE;
                            end
                        end else begin
                            write_idx <= write_idx + 5'd1;
                        end
                    end
                end

                ST_DONE: begin
                    state <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

    logic _unused;
    assign _unused = &{1'b0, cmd_accum, mac_busy};

endmodule
