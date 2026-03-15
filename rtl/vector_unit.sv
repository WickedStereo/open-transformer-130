module vector_unit #(
    parameter int NUM_BANKS   = 8,
    parameter int BANK_ADDR_W = 14,
    parameter int DATA_W      = 8,
    parameter int SLOT_BITS   = 5,
    parameter int MAX_COLS    = 64
) (
    input  logic                             clk,
    input  logic                             rst_n,

    // Command interface (from scheduler)
    input  logic                             cmd_valid,
    output logic                             cmd_ready,
    input  logic [SLOT_BITS-1:0]             cmd_src_slot,
    input  logic [SLOT_BITS-1:0]             cmd_dst_slot,
    input  logic [7:0]                       cmd_rows,
    input  logic [7:0]                       cmd_cols,
    input  logic                             cmd_approx,

    // Status
    output logic                             done,
    output logic                             busy,

    // Scratchpad bank arbiter (packed)
    output logic [NUM_BANKS-1:0]             scratch_req,
    output logic [NUM_BANKS*BANK_ADDR_W-1:0] scratch_addr,
    output logic [NUM_BANKS-1:0]             scratch_wen,
    output logic [NUM_BANKS*DATA_W-1:0]      scratch_wdata,
    input  logic [NUM_BANKS-1:0]             scratch_grant,
    input  logic [NUM_BANKS*DATA_W-1:0]      scratch_rdata
);

    // ── FSM states ──
    typedef enum logic [3:0] {
        ST_IDLE       = 4'd0,
        ST_READ_MAX   = 4'd1,  // Stage 1: read row, compute running max
        ST_MAX_DONE   = 4'd2,
        ST_READ_EXP   = 4'd3,  // Stage 2: re-read, subtract max, compute exp
        ST_SUM_DONE   = 4'd4,  // Stage 3: finalize sum
        ST_WRITE_OUT  = 4'd5,  // Stage 4: reciprocal-multiply, write INT8
        ST_ROW_DONE   = 4'd6,
        ST_TILE_DONE  = 4'd7
    } vec_state_t;

    vec_state_t state;

    // ── Latched command ──
    logic [SLOT_BITS-1:0] src_slot_r, dst_slot_r;
    logic [7:0]           num_rows_r, num_cols_r;
    logic                 approx_r;

    // ── Row processing counters ──
    logic [7:0] row_idx;
    logic [7:0] col_idx;

    // ── Local storage ──
    logic signed [31:0] row_max;
    logic [31:0]        row_sum;        // Q16.16 accumulator
    logic [15:0]        exp_buf [MAX_COLS]; // Q8.8 exp values

    // ── Scratchpad address computation ──
    // Source: INT32 scores -> 4 bytes per element
    // src_byte_addr = src_slot * 4096 + row_idx * num_cols * 4 + col_idx * 4 + byte_within
    logic [16:0] src_base;
    assign src_base = {src_slot_r, 12'b0};

    // Destination: INT8 weights -> 1 byte per element
    logic [16:0] dst_base;
    assign dst_base = {dst_slot_r, 12'b0};

    // Current byte address for reads (4 bytes per INT32 element, read byte by byte)
    logic [1:0]  byte_phase;  // which byte of the INT32 we're reading (0-3)
    logic [16:0] cur_read_addr;
    assign cur_read_addr = src_base + {1'b0, row_idx} * {9'b0, num_cols_r} * 17'd4
                           + {9'b0, col_idx} * 17'd4 + {15'b0, byte_phase};

    logic [16:0] cur_write_addr;
    assign cur_write_addr = dst_base + {1'b0, row_idx} * {9'b0, num_cols_r}
                            + {9'b0, col_idx};

    wire [2:0]             cur_bank   = cur_read_addr[16:14];
    wire [BANK_ADDR_W-1:0] cur_offset = cur_read_addr[BANK_ADDR_W-1:0];

    wire [2:0]             wr_bank    = cur_write_addr[16:14];
    wire [BANK_ADDR_W-1:0] wr_offset  = cur_write_addr[BANK_ADDR_W-1:0];

    // ── Temp register for accumulating INT32 reads from 4 byte reads ──
    logic [31:0] read_accum;

    // ── Exp approximation ──
    // shift-add with LUT: for x in [-255, 0], compute exp(x) as Q8.8
    // Clamp x < -16 to zero (output negligible)
    logic signed [31:0] shifted_score;

    // 32-entry LUT for fractional correction (Q0.8)
    // Maps frac = x - floor(x/ln2)*ln2 MSBs to exp(frac) approx
    // Pre-computed: exp(i/32 * ln(2)) * 256 for i=0..31
    logic [7:0] exp_frac_lut [32];
    initial begin
        exp_frac_lut[0]  = 8'd128; exp_frac_lut[1]  = 8'd131;
        exp_frac_lut[2]  = 8'd134; exp_frac_lut[3]  = 8'd137;
        exp_frac_lut[4]  = 8'd141; exp_frac_lut[5]  = 8'd144;
        exp_frac_lut[6]  = 8'd148; exp_frac_lut[7]  = 8'd151;
        exp_frac_lut[8]  = 8'd155; exp_frac_lut[9]  = 8'd159;
        exp_frac_lut[10] = 8'd163; exp_frac_lut[11] = 8'd167;
        exp_frac_lut[12] = 8'd171; exp_frac_lut[13] = 8'd175;
        exp_frac_lut[14] = 8'd179; exp_frac_lut[15] = 8'd184;
        exp_frac_lut[16] = 8'd188; exp_frac_lut[17] = 8'd193;
        exp_frac_lut[18] = 8'd197; exp_frac_lut[19] = 8'd202;
        exp_frac_lut[20] = 8'd207; exp_frac_lut[21] = 8'd212;
        exp_frac_lut[22] = 8'd217; exp_frac_lut[23] = 8'd223;
        exp_frac_lut[24] = 8'd228; exp_frac_lut[25] = 8'd234;
        exp_frac_lut[26] = 8'd240; exp_frac_lut[27] = 8'd245;
        exp_frac_lut[28] = 8'd251; exp_frac_lut[29] = 8'd253;
        exp_frac_lut[30] = 8'd255; exp_frac_lut[31] = 8'd255;
    end

    // Reciprocal LUT: 256 entries mapping 8 MSBs of row_sum to Q0.16 reciprocal
    // recip_lut[i] ≈ 65536 / (i+1) (clamped to 16 bits)
    logic [15:0] recip_lut [256];
    initial begin
        for (int i = 0; i < 256; i++) begin
            if (i == 0)
                recip_lut[i] = 16'hFFFF;
            else
                recip_lut[i] = 16'(65536 / (i + 1));
        end
    end

    function automatic [15:0] compute_exp(input signed [31:0] x);
        // exp(x) for x <= 0, output Q8.8
        logic signed [31:0] neg_x;
        logic [4:0] int_part;
        logic [4:0] frac_idx;
        logic [7:0] frac_val;
        logic [15:0] result;
        begin
            if (x >= 0) begin
                compute_exp = 16'h0100; // exp(0) = 1.0 in Q8.8
            end else begin
                neg_x = -x;
                if (neg_x > 32'sd16) begin
                    compute_exp = 16'h0000; // clamped to zero
                end else begin
                    // int_part = floor(-x), shift right by int_part
                    int_part = neg_x[4:0];
                    frac_idx = (neg_x[4:0] == 5'd0) ? 5'd0 :
                               neg_x[4:0]; // simplified fractional index
                    frac_val = exp_frac_lut[frac_idx];
                    result = {8'd0, frac_val} >> int_part;
                    compute_exp = result;
                end
            end
        end
    endfunction

    // ── Scratchpad interface ──
    always_comb begin
        scratch_req   = '0;
        scratch_addr  = '0;
        scratch_wen   = '0;
        scratch_wdata = '0;

        if (state == ST_READ_MAX || state == ST_READ_EXP) begin
            scratch_req[cur_bank] = 1'b1;
            scratch_addr[cur_bank*BANK_ADDR_W +: BANK_ADDR_W] = cur_offset;
        end else if (state == ST_WRITE_OUT) begin
            scratch_req[wr_bank] = 1'b1;
            scratch_addr[wr_bank*BANK_ADDR_W +: BANK_ADDR_W] = wr_offset;
            scratch_wen[wr_bank] = 1'b1;
            // Compute output: exp_buf[col_idx] * recip / 256, saturate to INT8
            scratch_wdata[wr_bank*DATA_W +: DATA_W] = compute_output_byte();
        end
    end

    function automatic [7:0] compute_output_byte();
        logic [15:0] exp_val;
        logic [7:0]  recip_idx;
        logic [15:0] recip_val;
        logic [31:0] product;
        logic [7:0]  result;
        begin
            exp_val = exp_buf[col_idx[5:0]];
            recip_idx = row_sum[23:16];
            recip_val = recip_lut[recip_idx];
            product = {16'd0, exp_val} * {16'd0, recip_val};
            result = product[23:16];
            if (result > 8'd127) result = 8'd127;
            compute_output_byte = result;
        end
    endfunction

    // ── Outputs ──
    assign cmd_ready = (state == ST_IDLE);
    assign busy      = (state != ST_IDLE);
    assign done      = (state == ST_TILE_DONE);

    // ── Main FSM ──
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state       <= ST_IDLE;
            src_slot_r  <= '0;
            dst_slot_r  <= '0;
            num_rows_r  <= '0;
            num_cols_r  <= '0;
            approx_r    <= 1'b0;
            row_idx     <= '0;
            col_idx     <= '0;
            byte_phase  <= '0;
            row_max     <= '0;
            row_sum     <= '0;
            read_accum  <= '0;
            for (int i = 0; i < MAX_COLS; i++)
                exp_buf[i] <= '0;
        end else begin
            case (state)
                ST_IDLE: begin
                    if (cmd_valid) begin
                        src_slot_r <= cmd_src_slot;
                        dst_slot_r <= cmd_dst_slot;
                        num_rows_r <= cmd_rows;
                        num_cols_r <= cmd_cols;
                        approx_r   <= cmd_approx;
                        row_idx    <= '0;
                        col_idx    <= '0;
                        byte_phase <= '0;
                        row_max    <= 32'sh80000000; // INT32_MIN
                        row_sum    <= '0;
                        state      <= ST_READ_MAX;
                    end
                end

                // Stage 1: Read INT32 scores byte-by-byte, track row max
                ST_READ_MAX: begin
                    if (scratch_grant[cur_bank]) begin
                        // Accumulate bytes into INT32 (little-endian)
                        read_accum[byte_phase*8 +: 8] <=
                            scratch_rdata[cur_bank*DATA_W +: DATA_W];

                        if (byte_phase == 2'd3) begin
                            // Complete INT32 assembled next cycle
                            byte_phase <= '0;
                            if ($signed({scratch_rdata[cur_bank*DATA_W +: DATA_W],
                                         read_accum[23:0]}) > row_max)
                                row_max <= $signed({scratch_rdata[cur_bank*DATA_W +: DATA_W],
                                                    read_accum[23:0]});

                            if (col_idx == num_cols_r - 8'd1) begin
                                col_idx <= '0;
                                state   <= ST_MAX_DONE;
                            end else begin
                                col_idx <= col_idx + 8'd1;
                            end
                        end else begin
                            byte_phase <= byte_phase + 2'd1;
                        end
                    end
                end

                ST_MAX_DONE: begin
                    // Reset for stage 2
                    col_idx    <= '0;
                    byte_phase <= '0;
                    row_sum    <= '0;
                    state      <= ST_READ_EXP;
                end

                // Stage 2: Re-read scores, compute exp(score - max), accumulate sum
                ST_READ_EXP: begin
                    if (scratch_grant[cur_bank]) begin
                        read_accum[byte_phase*8 +: 8] <=
                            scratch_rdata[cur_bank*DATA_W +: DATA_W];

                        if (byte_phase == 2'd3) begin
                            byte_phase <= '0;
                            // Compute shifted score and exp
                            shifted_score <= $signed({scratch_rdata[cur_bank*DATA_W +: DATA_W],
                                                      read_accum[23:0]}) - row_max;
                            begin
                                logic [15:0] ev;
                                ev = compute_exp(
                                    $signed({scratch_rdata[cur_bank*DATA_W +: DATA_W],
                                             read_accum[23:0]}) - row_max);
                                exp_buf[col_idx[5:0]] <= ev;
                                row_sum <= row_sum + {16'd0, ev};
                            end

                            if (col_idx == num_cols_r - 8'd1) begin
                                col_idx <= '0;
                                state   <= ST_SUM_DONE;
                            end else begin
                                col_idx <= col_idx + 8'd1;
                            end
                        end else begin
                            byte_phase <= byte_phase + 2'd1;
                        end
                    end
                end

                ST_SUM_DONE: begin
                    col_idx <= '0;
                    state   <= ST_WRITE_OUT;
                end

                // Stage 4: Reciprocal multiply and write INT8 outputs
                ST_WRITE_OUT: begin
                    if (scratch_grant[wr_bank]) begin
                        if (col_idx == num_cols_r - 8'd1) begin
                            state <= ST_ROW_DONE;
                        end else begin
                            col_idx <= col_idx + 8'd1;
                        end
                    end
                end

                ST_ROW_DONE: begin
                    if (row_idx == num_rows_r - 8'd1) begin
                        state <= ST_TILE_DONE;
                    end else begin
                        row_idx    <= row_idx + 8'd1;
                        col_idx    <= '0;
                        byte_phase <= '0;
                        row_max    <= 32'sh80000000;
                        row_sum    <= '0;
                        read_accum <= '0;
                        state      <= ST_READ_MAX;
                    end
                end

                ST_TILE_DONE: begin
                    state <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

    logic _unused;
    assign _unused = &{1'b0, approx_r, shifted_score, read_accum[31:24]};

endmodule
