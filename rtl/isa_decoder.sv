module isa_decoder (
    input  logic        clk,
    input  logic        rst_n,

    // Descriptor from queue controller
    input  logic        desc_valid,
    input  logic [63:0] desc_data,
    output logic        desc_consumed,

    // Default dimensions (from MMIO config)
    input  logic [7:0]  default_m,
    input  logic [7:0]  default_n,
    input  logic [7:0]  default_k,

    // Decoded action to scheduler
    output logic        action_valid,
    input  logic        action_ready,
    output logic [2:0]  action_type,
    output logic        action_load,
    output logic [4:0]  action_src_slot,
    output logic [4:0]  action_dst_slot,
    output logic [7:0]  action_dim_m,
    output logic [7:0]  action_dim_n,
    output logic [7:0]  action_dim_k,
    output logic [7:0]  action_flags,
    output logic [3:0]  action_tag,

    // Fault reporting
    output logic        fault_valid,
    output logic [1:0]  fault_cause,
    output logic [63:0] fault_descriptor,

    // Fault control
    input  logic        fault_clear,
    output logic        fault_active
);

    // ── Descriptor field extraction ──
    wire [7:0] opcode       = desc_data[63:56];
    wire [7:0] flags        = desc_data[55:48];
    wire [7:0] dst_tile_raw = desc_data[47:40];
    wire [7:0] src_tile_raw = desc_data[39:32];
    wire [7:0] dim_m_raw    = desc_data[31:24];
    wire [7:0] dim_n_raw    = desc_data[23:16];
    wire [7:0] dim_k_raw    = desc_data[15:8];
    wire [3:0] tag          = desc_data[7:4];
    wire [3:0] reserved     = desc_data[3:0];

    // ── Opcode constants ──
    localparam logic [7:0] OP_NOP        = 8'h00;
    localparam logic [7:0] OP_LOAD_TILE  = 8'h01;
    localparam logic [7:0] OP_STORE_TILE = 8'h02;
    localparam logic [7:0] OP_MATMUL     = 8'h03;
    localparam logic [7:0] OP_ACCUMULATE = 8'h04;
    localparam logic [7:0] OP_SOFTMAX    = 8'h05;
    localparam logic [7:0] OP_CONFIG     = 8'h06;
    localparam logic [7:0] OP_BARRIER    = 8'h07;

    // ── Action type encoding ──
    localparam logic [2:0] ACT_NOP     = 3'd0;
    localparam logic [2:0] ACT_DMA     = 3'd1;
    localparam logic [2:0] ACT_COMPUTE = 3'd2;
    localparam logic [2:0] ACT_VECTOR  = 3'd3;
    localparam logic [2:0] ACT_CONFIG  = 3'd4;
    localparam logic [2:0] ACT_BARRIER = 3'd5;

    // ── Fault cause encoding ──
    localparam logic [1:0] FC_RESERVED_FIELD = 2'b00;
    localparam logic [1:0] FC_INVALID_OPCODE = 2'b01;
    localparam logic [1:0] FC_TILE_OOB       = 2'b10;

    // ── Fault state ──
    logic fault_latched;
    assign fault_active = fault_latched;

    always_ff @(posedge clk) begin
        if (!rst_n)
            fault_latched <= 1'b0;
        else if (fault_clear)
            fault_latched <= 1'b0;
        else if (fault_valid)
            fault_latched <= 1'b1;
    end

    // ── Combinational decode ──
    // Fault detection (priority-ordered per spec)
    logic        is_fault;
    logic [1:0]  fault_cause_comb;

    // Tile ID OOB applicability per opcode
    logic needs_dst, needs_src;
    always_comb begin
        needs_dst = (opcode == OP_LOAD_TILE) || (opcode == OP_MATMUL) ||
                    (opcode == OP_ACCUMULATE) || (opcode == OP_SOFTMAX);
        needs_src = (opcode == OP_STORE_TILE) || (opcode == OP_MATMUL) ||
                    (opcode == OP_ACCUMULATE) || (opcode == OP_SOFTMAX);
    end

    always_comb begin
        is_fault = 1'b0;
        fault_cause_comb = FC_RESERVED_FIELD;

        if (reserved != 4'd0) begin
            is_fault = 1'b1;
            fault_cause_comb = FC_RESERVED_FIELD;
        end else if (opcode > OP_BARRIER) begin
            is_fault = 1'b1;
            fault_cause_comb = FC_INVALID_OPCODE;
        end else if ((needs_dst && dst_tile_raw[7:5] != 3'd0) ||
                     (needs_src && src_tile_raw[7:5] != 3'd0)) begin
            is_fault = 1'b1;
            fault_cause_comb = FC_TILE_OOB;
        end
    end

    // Dimension resolution: 0 means use default
    wire [7:0] resolved_m = (dim_m_raw == 8'd0) ? default_m : dim_m_raw;
    wire [7:0] resolved_n = (dim_n_raw == 8'd0) ? default_n : dim_n_raw;
    wire [7:0] resolved_k = (dim_k_raw == 8'd0) ? default_k : dim_k_raw;

    // Action type mapping
    logic [2:0] act_type_comb;
    logic       act_load_comb;
    always_comb begin
        act_type_comb = ACT_NOP;
        act_load_comb = 1'b0;

        case (opcode)
            OP_NOP:        act_type_comb = ACT_NOP;
            OP_LOAD_TILE:  begin act_type_comb = ACT_DMA; act_load_comb = 1'b1; end
            OP_STORE_TILE: begin act_type_comb = ACT_DMA; act_load_comb = 1'b0; end
            OP_MATMUL:     act_type_comb = ACT_COMPUTE;
            OP_ACCUMULATE: act_type_comb = ACT_COMPUTE;
            OP_SOFTMAX:    act_type_comb = ACT_VECTOR;
            OP_CONFIG:     act_type_comb = ACT_CONFIG;
            OP_BARRIER:    act_type_comb = ACT_BARRIER;
            default:       act_type_comb = ACT_NOP;
        endcase
    end

    // ── Output registration ──
    // Decoder is single-cycle: present decoded results when desc_valid is high
    // and no fault is latched. Hold outputs until action_ready.

    typedef enum logic [1:0] {
        DEC_IDLE = 2'd0,
        DEC_PRESENT = 2'd1,
        DEC_FAULT = 2'd2
    } dec_state_t;

    dec_state_t dec_state;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            dec_state        <= DEC_IDLE;
            action_valid     <= 1'b0;
            action_type      <= ACT_NOP;
            action_load      <= 1'b0;
            action_src_slot  <= '0;
            action_dst_slot  <= '0;
            action_dim_m     <= '0;
            action_dim_n     <= '0;
            action_dim_k     <= '0;
            action_flags     <= '0;
            action_tag       <= '0;
            fault_valid      <= 1'b0;
            fault_cause      <= '0;
            fault_descriptor <= '0;
            desc_consumed    <= 1'b0;
        end else begin
            desc_consumed <= 1'b0;
            fault_valid   <= 1'b0;

            case (dec_state)
                DEC_IDLE: begin
                    if (desc_valid && !fault_latched) begin
                        if (is_fault) begin
                            fault_valid      <= 1'b1;
                            fault_cause      <= fault_cause_comb;
                            fault_descriptor <= desc_data;
                            desc_consumed    <= 1'b1;
                            action_valid     <= 1'b0;
                            dec_state        <= DEC_IDLE;
                        end else begin
                            action_valid    <= 1'b1;
                            action_type     <= act_type_comb;
                            action_load     <= act_load_comb;
                            action_src_slot <= src_tile_raw[4:0];
                            action_dst_slot <= dst_tile_raw[4:0];
                            action_dim_m    <= resolved_m;
                            action_dim_n    <= resolved_n;
                            action_dim_k    <= resolved_k;
                            action_flags    <= flags;
                            action_tag      <= tag;
                            dec_state       <= DEC_PRESENT;
                        end
                    end
                end

                DEC_PRESENT: begin
                    if (action_ready) begin
                        action_valid  <= 1'b0;
                        desc_consumed <= 1'b1;
                        dec_state     <= DEC_IDLE;
                    end
                end

                default: dec_state <= DEC_IDLE;
            endcase
        end
    end

endmodule
