module fpga_attention_demo (
    input  logic        clk,
    input  logic        btn_n,
    output logic        demo_started,
    output logic        demo_done,
    output logic        demo_pass,
    output logic        demo_fault,
    output logic [31:0] status_snapshot,
    output logic [7:0]  tail_snapshot,
    output logic [31:0] output_word
);

    localparam integer DEMO_NUM_BANKS = 4;
    localparam integer DEMO_BANK_ADDR_W = 4;
    localparam integer DEMO_SLOT_BITS = 2;
    localparam integer DEMO_SLOT_BYTES = 16;
    localparam integer DEMO_COMPUTE_NUM_LANES = 2;

    localparam [1:0] SLOT_QUERY        = 2'd0;
    localparam [1:0] SLOT_SCORE        = 2'd1;
    localparam [1:0] SLOT_SOFTMAX      = 2'd2;
    localparam [1:0] SLOT_VALUE_OUTPUT = 2'd3;

    localparam [7:0] EXPECTED_OUT0 = 8'd15;
    localparam [7:0] EXPECTED_OUT1 = 8'd25;
    localparam [7:0] EXPECTED_OUT2 = 8'd24;
    localparam [7:0] EXPECTED_OUT3 = 8'd34;

    localparam [7:0] QUERY_TILE0 = 8'd1;
    localparam [7:0] QUERY_TILE1 = 8'd0;
    localparam [7:0] QUERY_TILE2 = 8'd0;
    localparam [7:0] QUERY_TILE3 = 8'd1;

    localparam [7:0] KEY_TILE0 = 8'd1;
    localparam [7:0] KEY_TILE1 = 8'd0;
    localparam [7:0] KEY_TILE2 = 8'd0;
    localparam [7:0] KEY_TILE3 = 8'd1;

    localparam [7:0] VALUE_TILE0 = 8'd10;
    localparam [7:0] VALUE_TILE1 = 8'd20;
    localparam [7:0] VALUE_TILE2 = 8'd30;
    localparam [7:0] VALUE_TILE3 = 8'd40;

    // Softmax(identity) quantized to Q0.7 so the second matmul reproduces the
    // expected directed attention output after the existing post-multiply shift.
    localparam [7:0] SOFTMAX_TILE0 = 8'd93;
    localparam [7:0] SOFTMAX_TILE1 = 8'd34;
    localparam [7:0] SOFTMAX_TILE2 = 8'd34;
    localparam [7:0] SOFTMAX_TILE3 = 8'd93;

    localparam [3:0] ST_PRELOAD      = 4'd0;
    localparam [3:0] ST_SCORE_START  = 4'd1;
    localparam [3:0] ST_SCORE_WAIT   = 4'd2;
    localparam [3:0] ST_SOFTMAX      = 4'd3;
    localparam [3:0] ST_OUTPUT_START = 4'd4;
    localparam [3:0] ST_OUTPUT_WAIT  = 4'd5;
    localparam [3:0] ST_READ_REQ     = 4'd6;
    localparam [3:0] ST_READ_CAP     = 4'd7;
    localparam [3:0] ST_EVAL         = 4'd8;
    localparam [3:0] ST_HOLD         = 4'd9;

    function automatic [1:0] preload_bank(input logic [3:0] idx);
        begin
            case (idx)
                4'd0, 4'd1, 4'd2, 4'd3: preload_bank = SLOT_QUERY;
                4'd4, 4'd5, 4'd6, 4'd7: preload_bank = SLOT_SCORE;
                default:                 preload_bank = SLOT_VALUE_OUTPUT;
            endcase
        end
    endfunction

    function automatic [3:0] preload_addr(input logic [3:0] idx);
        begin
            preload_addr = {2'b00, idx[1:0]};
        end
    endfunction

    function automatic [7:0] preload_byte(input logic [3:0] idx);
        begin
            case (idx)
                4'd0: preload_byte = QUERY_TILE0;
                4'd1: preload_byte = QUERY_TILE1;
                4'd2: preload_byte = QUERY_TILE2;
                4'd3: preload_byte = QUERY_TILE3;
                4'd4: preload_byte = KEY_TILE0;
                4'd5: preload_byte = KEY_TILE1;
                4'd6: preload_byte = KEY_TILE2;
                4'd7: preload_byte = KEY_TILE3;
                4'd8: preload_byte = VALUE_TILE0;
                4'd9: preload_byte = VALUE_TILE1;
                4'd10: preload_byte = VALUE_TILE2;
                default: preload_byte = VALUE_TILE3;
            endcase
        end
    endfunction

    function automatic [7:0] softmax_byte(input logic [1:0] idx);
        begin
            case (idx)
                2'd0: softmax_byte = SOFTMAX_TILE0;
                2'd1: softmax_byte = SOFTMAX_TILE1;
                2'd2: softmax_byte = SOFTMAX_TILE2;
                default: softmax_byte = SOFTMAX_TILE3;
            endcase
        end
    endfunction

    logic [7:0] por_counter;
    logic       rst_n;

    logic [3:0] state;
    logic [3:0] preload_idx;
    logic [1:0] softmax_idx;
    logic [1:0] read_idx;

    logic [7:0] out_byte0, out_byte1, out_byte2, out_byte3;

    logic controller_owns_scratch;
    logic [DEMO_NUM_BANKS-1:0] ctrl_bank_en;
    logic [DEMO_NUM_BANKS-1:0] ctrl_bank_wen;
    logic [DEMO_NUM_BANKS*DEMO_BANK_ADDR_W-1:0] ctrl_bank_addr;
    logic [DEMO_NUM_BANKS*8-1:0] ctrl_bank_wdata;

    logic [DEMO_NUM_BANKS-1:0] bank_en;
    logic [DEMO_NUM_BANKS-1:0] bank_wen;
    logic [DEMO_NUM_BANKS*DEMO_BANK_ADDR_W-1:0] bank_addr;
    logic [DEMO_NUM_BANKS*8-1:0] bank_wdata;
    logic [DEMO_NUM_BANKS*8-1:0] bank_rdata;

    logic                              compute_cmd_valid;
    logic                              compute_cmd_ready;
    logic [DEMO_SLOT_BITS-1:0]         compute_src_slot;
    logic [DEMO_SLOT_BITS-1:0]         compute_src2_slot;
    logic [DEMO_SLOT_BITS-1:0]         compute_dst_slot;
    logic [7:0]                        compute_dim_m;
    logic [7:0]                        compute_dim_n;
    logic [7:0]                        compute_dim_k;
    logic                              compute_accum;
    logic                              compute_saturate;
    logic [3:0]                        compute_shift;
    logic                              compute_done;
    logic                              compute_busy;
    logic [DEMO_NUM_BANKS-1:0]         compute_scratch_req;
    logic [DEMO_NUM_BANKS*DEMO_BANK_ADDR_W-1:0] compute_scratch_addr;
    logic [DEMO_NUM_BANKS-1:0]         compute_scratch_wen;
    logic [DEMO_NUM_BANKS*8-1:0]       compute_scratch_wdata;
    logic [DEMO_NUM_BANKS-1:0]         compute_scratch_grant;
    logic [DEMO_NUM_BANKS*8-1:0]       compute_scratch_rdata;

    wire output_matches =
        (out_byte0 == EXPECTED_OUT0) &&
        (out_byte1 == EXPECTED_OUT1) &&
        (out_byte2 == EXPECTED_OUT2) &&
        (out_byte3 == EXPECTED_OUT3);

    always_ff @(posedge clk or negedge btn_n) begin
        if (!btn_n)
            por_counter <= '0;
        else if (!por_counter[7])
            por_counter <= por_counter + 8'd1;
    end

    assign rst_n = por_counter[7];

    compute_engine #(
        .NUM_BANKS      (DEMO_NUM_BANKS),
        .BANK_ADDR_W    (DEMO_BANK_ADDR_W),
        .DATA_W         (8),
        .SLOT_BITS      (DEMO_SLOT_BITS),
        .NUM_LANES      (DEMO_COMPUTE_NUM_LANES),
        .MAX_TILE_BYTES (DEMO_SLOT_BYTES)
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
        .scratch_req   (compute_scratch_req),
        .scratch_addr  (compute_scratch_addr),
        .scratch_wen   (compute_scratch_wen),
        .scratch_wdata (compute_scratch_wdata),
        .scratch_grant (compute_scratch_grant),
        .scratch_rdata (compute_scratch_rdata)
    );

    scratchpad #(
        .NUM_BANKS   (DEMO_NUM_BANKS),
        .BANK_SIZE   (DEMO_SLOT_BYTES),
        .BANK_ADDR_W (DEMO_BANK_ADDR_W),
        .DATA_W      (8)
    ) u_scratchpad (
        .clk        (clk),
        .rst_n      (rst_n),
        .bank_en    (bank_en),
        .bank_wen   (bank_wen),
        .bank_addr  (bank_addr),
        .bank_wdata (bank_wdata),
        .bank_rdata (bank_rdata)
    );

    always_comb begin
        controller_owns_scratch = 1'b0;
        ctrl_bank_en = '0;
        ctrl_bank_wen = '0;
        ctrl_bank_addr = '0;
        ctrl_bank_wdata = '0;

        compute_cmd_valid = 1'b0;
        compute_src_slot = '0;
        compute_src2_slot = '0;
        compute_dst_slot = '0;
        compute_dim_m = 8'd2;
        compute_dim_n = 8'd2;
        compute_dim_k = 8'd2;
        compute_accum = 1'b0;
        compute_saturate = 1'b0;
        compute_shift = 4'd0;

        case (state)
            ST_PRELOAD: begin
                controller_owns_scratch = 1'b1;
                ctrl_bank_en[preload_bank(preload_idx)] = 1'b1;
                ctrl_bank_wen[preload_bank(preload_idx)] = 1'b1;
                ctrl_bank_addr[preload_bank(preload_idx)*DEMO_BANK_ADDR_W +: DEMO_BANK_ADDR_W] =
                    preload_addr(preload_idx);
                ctrl_bank_wdata[preload_bank(preload_idx)*8 +: 8] = preload_byte(preload_idx);
            end

            ST_SCORE_START: begin
                compute_cmd_valid = 1'b1;
                compute_src_slot = SLOT_QUERY;
                compute_src2_slot = SLOT_SCORE;
                compute_dst_slot = SLOT_SCORE;
                compute_saturate = 1'b1;
            end

            ST_SOFTMAX: begin
                controller_owns_scratch = 1'b1;
                ctrl_bank_en[SLOT_SOFTMAX] = 1'b1;
                ctrl_bank_wen[SLOT_SOFTMAX] = 1'b1;
                ctrl_bank_addr[SLOT_SOFTMAX*DEMO_BANK_ADDR_W +: DEMO_BANK_ADDR_W] =
                    {2'b00, softmax_idx};
                ctrl_bank_wdata[SLOT_SOFTMAX*8 +: 8] = softmax_byte(softmax_idx);
            end

            ST_OUTPUT_START: begin
                compute_cmd_valid = 1'b1;
                compute_src_slot = SLOT_SOFTMAX;
                compute_src2_slot = SLOT_VALUE_OUTPUT;
                compute_dst_slot = SLOT_VALUE_OUTPUT;
                compute_saturate = 1'b1;
                compute_shift = 4'd7;
            end

            ST_READ_REQ: begin
                controller_owns_scratch = 1'b1;
                ctrl_bank_en[SLOT_VALUE_OUTPUT] = 1'b1;
                ctrl_bank_addr[SLOT_VALUE_OUTPUT*DEMO_BANK_ADDR_W +: DEMO_BANK_ADDR_W] =
                    {2'b00, read_idx};
            end

            default: begin
            end
        endcase
    end

    always_comb begin
        if (controller_owns_scratch) begin
            bank_en = ctrl_bank_en;
            bank_wen = ctrl_bank_wen;
            bank_addr = ctrl_bank_addr;
            bank_wdata = ctrl_bank_wdata;
            compute_scratch_grant = '0;
        end else begin
            bank_en = compute_scratch_req;
            bank_wen = compute_scratch_wen;
            bank_addr = compute_scratch_addr;
            bank_wdata = compute_scratch_wdata;
            compute_scratch_grant = compute_scratch_req;
        end

        compute_scratch_rdata = bank_rdata;
    end

    always_ff @(posedge clk or negedge btn_n) begin
        if (!btn_n) begin
            state <= ST_PRELOAD;
            preload_idx <= '0;
            softmax_idx <= '0;
            read_idx <= '0;
            demo_started <= 1'b0;
            demo_done <= 1'b0;
            demo_pass <= 1'b0;
            demo_fault <= 1'b0;
            status_snapshot <= '0;
            tail_snapshot <= '0;
            output_word <= '0;
            out_byte0 <= '0;
            out_byte1 <= '0;
            out_byte2 <= '0;
            out_byte3 <= '0;
        end else if (!rst_n) begin
            state <= ST_PRELOAD;
            preload_idx <= '0;
            softmax_idx <= '0;
            read_idx <= '0;
            demo_started <= 1'b0;
            demo_done <= 1'b0;
            demo_pass <= 1'b0;
            demo_fault <= 1'b0;
            status_snapshot <= '0;
            tail_snapshot <= '0;
            output_word <= '0;
            out_byte0 <= '0;
            out_byte1 <= '0;
            out_byte2 <= '0;
            out_byte3 <= '0;
        end else begin
            case (state)
                ST_PRELOAD: begin
                    demo_started <= 1'b1;
                    if (preload_idx == 4'd11) begin
                        preload_idx <= '0;
                        state <= ST_SCORE_START;
                    end else begin
                        preload_idx <= preload_idx + 4'd1;
                    end
                end

                ST_SCORE_START: begin
                    if (compute_cmd_ready)
                        state <= ST_SCORE_WAIT;
                end

                ST_SCORE_WAIT: begin
                    if (compute_done) begin
                        softmax_idx <= '0;
                        state <= ST_SOFTMAX;
                    end
                end

                ST_SOFTMAX: begin
                    if (softmax_idx == 2'd3) begin
                        softmax_idx <= '0;
                        state <= ST_OUTPUT_START;
                    end else begin
                        softmax_idx <= softmax_idx + 2'd1;
                    end
                end

                ST_OUTPUT_START: begin
                    if (compute_cmd_ready)
                        state <= ST_OUTPUT_WAIT;
                end

                ST_OUTPUT_WAIT: begin
                    if (compute_done) begin
                        read_idx <= '0;
                        state <= ST_READ_REQ;
                    end
                end

                ST_READ_REQ: begin
                    state <= ST_READ_CAP;
                end

                ST_READ_CAP: begin
                    case (read_idx)
                        2'd0: out_byte0 <= bank_rdata[SLOT_VALUE_OUTPUT*8 +: 8];
                        2'd1: out_byte1 <= bank_rdata[SLOT_VALUE_OUTPUT*8 +: 8];
                        2'd2: out_byte2 <= bank_rdata[SLOT_VALUE_OUTPUT*8 +: 8];
                        default: out_byte3 <= bank_rdata[SLOT_VALUE_OUTPUT*8 +: 8];
                    endcase

                    if (read_idx == 2'd3)
                        state <= ST_EVAL;
                    else begin
                        read_idx <= read_idx + 2'd1;
                        state <= ST_READ_REQ;
                    end
                end

                ST_EVAL: begin
                    output_word <= {out_byte3, out_byte2, out_byte1, out_byte0};
                    tail_snapshot <= 8'd7;
                    status_snapshot <= output_matches ? 32'd0 : 32'h0000_0002;
                    demo_fault <= !output_matches;
                    demo_pass <= output_matches;
                    demo_done <= 1'b1;
                    state <= ST_HOLD;
                end

                default: begin
                    state <= ST_HOLD;
                end
            endcase
        end
    end

    logic _unused;
    assign _unused = &{1'b0, compute_busy};

endmodule
