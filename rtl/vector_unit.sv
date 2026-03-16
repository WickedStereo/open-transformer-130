module vector_unit #(
    parameter NUM_BANKS   = 8,
    parameter BANK_ADDR_W = 14,
    parameter DATA_W      = 8,
    parameter SLOT_BITS   = 5,
    parameter MAX_COLS    = 64
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

    localparam ST_IDLE      = 3'd0;
    localparam ST_MAX_REQ   = 3'd1;
    localparam ST_MAX_DATA  = 3'd2;
    localparam ST_EXP_REQ   = 3'd3;
    localparam ST_EXP_DATA  = 3'd4;
    localparam ST_WRITE_OUT = 3'd5;
    localparam ST_ROW_DONE  = 3'd6;
    localparam ST_TILE_DONE = 3'd7;
    localparam integer LOCAL_ADDR_W = 17;
    localparam integer BANK_BITS = (NUM_BANKS > 1) ? $clog2(NUM_BANKS) : 1;
    localparam integer SLOT_ADDR_W = BANK_ADDR_W + BANK_BITS - SLOT_BITS;

    logic [2:0] state;

    logic [SLOT_BITS-1:0] src_slot_r, dst_slot_r;
    logic [7:0]           num_rows_r, num_cols_r;
    logic                 approx_r;
    logic [7:0]           row_idx, col_idx;
    logic [BANK_BITS-1:0] read_bank_r;
    logic signed [8:0]    row_max;
    logic [31:0]          row_sum;
    logic [15:0]          exp_buf [0:MAX_COLS-1];
    logic signed [8:0]    read_score;
    logic signed [8:0]    shifted_score;
    logic [15:0]          exp_value_w;
    integer               exp_init_idx;

    logic [LOCAL_ADDR_W-1:0] src_base, dst_base, cur_addr;
    assign src_base = {
        {(LOCAL_ADDR_W - SLOT_BITS - SLOT_ADDR_W){1'b0}},
        src_slot_r,
        {SLOT_ADDR_W{1'b0}}
    };
    assign dst_base = {
        {(LOCAL_ADDR_W - SLOT_BITS - SLOT_ADDR_W){1'b0}},
        dst_slot_r,
        {SLOT_ADDR_W{1'b0}}
    };

    always_comb begin
        if (state == ST_WRITE_OUT)
            cur_addr = dst_base + ({9'b0, row_idx} * {9'b0, num_cols_r}) + {9'b0, col_idx};
        else
            cur_addr = src_base + ({9'b0, row_idx} * {9'b0, num_cols_r}) + {9'b0, col_idx};
    end

    wire [BANK_BITS-1:0]   cur_bank   = cur_addr[BANK_ADDR_W + BANK_BITS - 1 -: BANK_BITS];
    wire [BANK_ADDR_W-1:0] cur_offset = cur_addr[BANK_ADDR_W-1:0];
    assign read_score = signed_byte(scratch_rdata[read_bank_r*DATA_W +: DATA_W]);
    assign shifted_score = read_score - row_max;
    assign exp_value_w = compute_exp(shifted_score);

    logic [15:0] exp_lut [0:16];
    initial begin
        exp_lut[0]  = 16'd256;
        exp_lut[1]  = 16'd94;
        exp_lut[2]  = 16'd35;
        exp_lut[3]  = 16'd13;
        exp_lut[4]  = 16'd5;
        exp_lut[5]  = 16'd2;
        exp_lut[6]  = 16'd1;
        exp_lut[7]  = 16'd0;
        exp_lut[8]  = 16'd0;
        exp_lut[9]  = 16'd0;
        exp_lut[10] = 16'd0;
        exp_lut[11] = 16'd0;
        exp_lut[12] = 16'd0;
        exp_lut[13] = 16'd0;
        exp_lut[14] = 16'd0;
        exp_lut[15] = 16'd0;
        exp_lut[16] = 16'd0;
    end

    function automatic [8:0] signed_byte;
        input [7:0] value;
        begin
            signed_byte = $signed({value[7], value});
        end
    endfunction

    function automatic [15:0] compute_exp;
        input signed [8:0] shifted;
        reg [8:0] magnitude;
        begin
            if (shifted >= 0) begin
                compute_exp = 16'd256;
            end else begin
                magnitude = -shifted;
                if (magnitude > 9'd16)
                    compute_exp = 16'd0;
                else
                    compute_exp = exp_lut[magnitude[4:0]];
            end
        end
    endfunction

    function automatic [7:0] normalized_byte;
        input [15:0] exp_value;
        input [31:0] sum_value;
        reg [31:0] scaled;
        begin
            if (sum_value == 32'd0) begin
                normalized_byte = 8'd0;
            end else begin
                scaled = ({16'd0, exp_value} * 32'd127 + (sum_value >> 1)) / sum_value;
                if (scaled > 32'd127)
                    normalized_byte = 8'd127;
                else
                    normalized_byte = scaled[7:0];
            end
        end
    endfunction

    always_comb begin
        scratch_req   = '0;
        scratch_addr  = '0;
        scratch_wen   = '0;
        scratch_wdata = '0;

        if (state == ST_MAX_REQ || state == ST_EXP_REQ || state == ST_WRITE_OUT) begin
            scratch_req[cur_bank] = 1'b1;
            scratch_addr[cur_bank*BANK_ADDR_W +: BANK_ADDR_W] = cur_offset;
            if (state == ST_WRITE_OUT) begin
                scratch_wen[cur_bank] = 1'b1;
                scratch_wdata[cur_bank*DATA_W +: DATA_W] = normalized_byte(
                    exp_buf[col_idx[5:0]],
                    row_sum
                );
            end
        end
    end

    assign cmd_ready = (state == ST_IDLE);
    assign busy      = (state != ST_IDLE);
    assign done      = (state == ST_TILE_DONE);

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state      <= ST_IDLE;
            src_slot_r <= '0;
            dst_slot_r <= '0;
            num_rows_r <= '0;
            num_cols_r <= '0;
            approx_r   <= 1'b0;
            row_idx    <= '0;
            col_idx    <= '0;
            read_bank_r<= '0;
            row_max    <= -9'sd128;
            row_sum    <= '0;
            for (exp_init_idx = 0; exp_init_idx < MAX_COLS; exp_init_idx = exp_init_idx + 1)
                exp_buf[exp_init_idx] <= '0;
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
                        row_max    <= -9'sd128;
                        row_sum    <= '0;
                        state      <= ST_MAX_REQ;
                    end
                end

                ST_MAX_REQ: begin
                    if (scratch_grant[cur_bank]) begin
                        read_bank_r <= cur_bank;
                        state       <= ST_MAX_DATA;
                    end
                end

                ST_MAX_DATA: begin
                    if (read_score > row_max)
                        row_max <= read_score;

                    if (col_idx + 8'd1 >= num_cols_r) begin
                        col_idx <= '0;
                        row_sum <= '0;
                        state   <= ST_EXP_REQ;
                    end else begin
                        col_idx <= col_idx + 8'd1;
                        state   <= ST_MAX_REQ;
                    end
                end

                ST_EXP_REQ: begin
                    if (scratch_grant[cur_bank]) begin
                        read_bank_r <= cur_bank;
                        state       <= ST_EXP_DATA;
                    end
                end

                ST_EXP_DATA: begin
                    exp_buf[col_idx[5:0]] <= exp_value_w;
                    row_sum <= row_sum + {16'd0, exp_value_w};

                    if (col_idx + 8'd1 >= num_cols_r) begin
                        col_idx <= '0;
                        state   <= ST_WRITE_OUT;
                    end else begin
                        col_idx <= col_idx + 8'd1;
                        state   <= ST_EXP_REQ;
                    end
                end

                ST_WRITE_OUT: begin
                    if (scratch_grant[cur_bank]) begin
                        if (col_idx + 8'd1 >= num_cols_r) begin
                            state <= ST_ROW_DONE;
                        end else begin
                            col_idx <= col_idx + 8'd1;
                        end
                    end
                end

                ST_ROW_DONE: begin
                    if (row_idx + 8'd1 >= num_rows_r) begin
                        state <= ST_TILE_DONE;
                    end else begin
                        row_idx <= row_idx + 8'd1;
                        col_idx <= '0;
                        row_max <= -9'sd128;
                        row_sum <= '0;
                        state   <= ST_MAX_REQ;
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
    assign _unused = &{1'b0, approx_r};

endmodule
