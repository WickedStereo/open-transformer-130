module mac_array #(
    parameter NUM_LANES     = 16,
    parameter OPERAND_WIDTH = 8,
    parameter ACCUM_WIDTH   = 32
) (
    input  logic                                clk,
    input  logic                                rst_n,

    // Tile command handshake
    input  logic                                tile_valid,
    output logic                                tile_ready,
    input  logic [7:0]                          tile_m,
    input  logic [7:0]                          tile_n,
    input  logic [7:0]                          tile_k,
    input  logic                                accum_mode,

    // Operand data (16 × INT8 per side, fed by external data-fetch logic)
    input  logic [NUM_LANES*OPERAND_WIDTH-1:0]  a_data,
    input  logic [NUM_LANES*OPERAND_WIDTH-1:0]  b_data,
    input  logic                                a_valid,
    input  logic                                b_valid,

    // Result output (16 × INT32, one row-group at a time)
    output logic [NUM_LANES*ACCUM_WIDTH-1:0]    result_data,
    output logic                                result_valid,
    input  logic                                result_ready,

    output logic                                busy
);

    // ── FSM states ──
    localparam S_IDLE    = 3'd0;
    localparam S_COMPUTE = 3'd1;
    localparam S_DRAIN   = 3'd2;
    localparam S_OUTPUT  = 3'd3;

    logic [2:0] state;

    // Latched tile dimensions
    logic [7:0] dim_m_r, dim_k_r;
    logic       acc_mode_r;
    logic [4:0] num_groups_r;

    // Counters
    logic [7:0] row_cnt;
    logic [4:0] group_cnt;
    logic [7:0] k_cnt;
    logic [1:0] drain_cnt;

    // ceil(tile_n / NUM_LANES) -- evaluated when tile_valid is sampled
    // For NUM_LANES=16: upper nibble + (lower nibble != 0)
    wire [4:0] groups_calc = {1'b0, tile_n[7:4]} + {4'd0, |tile_n[3:0]};

    // ── Lane control signals ──
    logic data_consumed;
    assign data_consumed = (state == S_COMPUTE) && a_valid && b_valid;

    logic lane_op_valid;
    assign lane_op_valid = data_consumed;

    logic lane_accum_clear;
    assign lane_accum_clear = data_consumed && (k_cnt == 8'd0)
                              && !(acc_mode_r && row_cnt == 8'd0 && group_cnt == 5'd0);

    // ── Lane instantiation ──
    logic [ACCUM_WIDTH-1:0] lane_accum  [NUM_LANES];
    logic [NUM_LANES-1:0]   lane_busy_w;

    genvar gi;
    generate
        for (gi = 0; gi < NUM_LANES; gi++) begin : gen_lanes
            mac_lane #(
                .OPERAND_WIDTH (OPERAND_WIDTH),
                .ACCUM_WIDTH   (ACCUM_WIDTH)
            ) u_lane (
                .clk         (clk),
                .rst_n       (rst_n),
                .op_valid    (lane_op_valid),
                .op_a        (a_data[gi*OPERAND_WIDTH +: OPERAND_WIDTH]),
                .op_b        (b_data[gi*OPERAND_WIDTH +: OPERAND_WIDTH]),
                .accum_clear (lane_accum_clear),
                .accum_out   (lane_accum[gi]),
                .lane_busy   (lane_busy_w[gi])
            );
        end
    endgenerate

    // Pack lane accumulators into result bus
    generate
        for (gi = 0; gi < NUM_LANES; gi++) begin : gen_pack
            assign result_data[gi*ACCUM_WIDTH +: ACCUM_WIDTH] = lane_accum[gi];
        end
    endgenerate

    // ── Output control ──
    assign tile_ready   = (state == S_IDLE);
    assign result_valid = (state == S_OUTPUT);
    assign busy         = (state != S_IDLE);

    // ── Main state machine ──
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state        <= S_IDLE;
            dim_m_r      <= '0;
            dim_k_r      <= '0;
            acc_mode_r   <= 1'b0;
            num_groups_r <= '0;
            row_cnt      <= '0;
            group_cnt    <= '0;
            k_cnt        <= '0;
            drain_cnt    <= '0;
        end else begin
            case (state)
                S_IDLE: begin
                    if (tile_valid) begin
                        dim_m_r      <= tile_m;
                        dim_k_r      <= tile_k;
                        acc_mode_r   <= accum_mode;
                        num_groups_r <= groups_calc;
                        row_cnt      <= '0;
                        group_cnt    <= '0;
                        k_cnt        <= '0;
                        state        <= S_COMPUTE;
                    end
                end

                S_COMPUTE: begin
                    if (data_consumed) begin
                        if (k_cnt == dim_k_r - 8'd1) begin
                            drain_cnt <= '0;
                            state     <= S_DRAIN;
                        end else begin
                            k_cnt <= k_cnt + 8'd1;
                        end
                    end
                end

                S_DRAIN: begin
                    if (drain_cnt == 2'd1) begin
                        state <= S_OUTPUT;
                    end else begin
                        drain_cnt <= drain_cnt + 2'd1;
                    end
                end

                S_OUTPUT: begin
                    if (result_ready) begin
                        if (group_cnt == num_groups_r - 5'd1) begin
                            if (row_cnt == dim_m_r - 8'd1) begin
                                state <= S_IDLE;
                            end else begin
                                row_cnt   <= row_cnt + 8'd1;
                                group_cnt <= '0;
                                k_cnt     <= '0;
                                state     <= S_COMPUTE;
                            end
                        end else begin
                            group_cnt <= group_cnt + 5'd1;
                            k_cnt     <= '0;
                            state     <= S_COMPUTE;
                        end
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

    // Suppress Verilator warnings for signals used only by child instances
    logic _unused;
    assign _unused = &{1'b0, lane_busy_w};

endmodule
