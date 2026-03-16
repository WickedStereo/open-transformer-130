module dma_engine #(
    parameter NUM_BANKS   = 8,
    parameter BANK_ADDR_W = 14,
    parameter DATA_W      = 8,
    parameter SLOT_BITS   = 5
) (
    input  logic                              clk,
    input  logic                              rst_n,

    // Command interface (from scheduler)
    input  logic                              cmd_valid,
    output logic                              cmd_ready,
    input  logic                              cmd_load,
    input  logic [31:0]                       cmd_host_addr,
    input  logic [SLOT_BITS-1:0]              cmd_slot_id,
    input  logic [12:0]                       cmd_byte_count,

    // Completion
    output logic                              done,
    output logic                              error,
    output logic [31:0]                       bytes_moved,

    // Host bus (16-byte burst)
    output logic                              bus_req,
    output logic [31:0]                       bus_addr,
    output logic                              bus_wen,
    output logic [127:0]                      bus_wdata,
    input  logic [127:0]                      bus_rdata,
    input  logic                              bus_ack,

    // Scratchpad bank arbiter (packed)
    output logic [NUM_BANKS-1:0]              scratch_req,
    output logic [NUM_BANKS*BANK_ADDR_W-1:0]  scratch_addr,
    output logic [NUM_BANKS-1:0]              scratch_wen,
    output logic [NUM_BANKS*DATA_W-1:0]       scratch_wdata,
    input  logic [NUM_BANKS-1:0]              scratch_grant,
    input  logic [NUM_BANKS*DATA_W-1:0]       scratch_rdata
);

    localparam S_IDLE          = 3'd0;
    localparam S_BUS_REQ       = 3'd1;
    localparam S_SCRATCH_REQ   = 3'd2;
    localparam S_SCRATCH_DATA  = 3'd3;
    localparam S_SCRATCH_WRITE = 3'd4;
    localparam S_DONE          = 3'd5;
    localparam S_ERROR         = 3'd6;
    localparam integer LOCAL_ADDR_W = 17;
    localparam integer BANK_BITS = (NUM_BANKS > 1) ? $clog2(NUM_BANKS) : 1;
    localparam integer SLOT_ADDR_W = BANK_ADDR_W + BANK_BITS - SLOT_BITS;

    logic [2:0] state;

    logic        load_r;
    logic [31:0] host_addr_r;
    logic [LOCAL_ADDR_W-1:0] scratch_base_r;
    logic [12:0] total_bytes_r;
    logic [12:0] xfer_count;
    logic [31:0] byte_counter;

    logic [127:0] burst_buf;
    logic [3:0]   burst_idx;
    logic [4:0]   burst_len_r;
    logic [BANK_BITS-1:0] read_bank_r;

    logic [LOCAL_ADDR_W-1:0] scratch_byte_addr;
    wire [12:0] bytes_remaining = total_bytes_r - xfer_count;

    function automatic [4:0] burst_len_for(input logic [12:0] remaining);
        begin
            if (remaining >= 13'd16)
                burst_len_for = 5'd16;
            else
                burst_len_for = {1'b0, remaining[3:0]};
        end
    endfunction

    assign scratch_byte_addr = scratch_base_r + {4'b0, xfer_count} + {13'b0, burst_idx};

    wire [BANK_BITS-1:0]   cur_bank   = scratch_byte_addr[BANK_ADDR_W + BANK_BITS - 1 -: BANK_BITS];
    wire [BANK_ADDR_W-1:0] cur_offset = scratch_byte_addr[BANK_ADDR_W-1:0];

    assign cmd_ready   = (state == S_IDLE);
    assign done        = (state == S_DONE);
    assign error       = (state == S_ERROR);
    assign bytes_moved = byte_counter;

    assign bus_req   = (state == S_BUS_REQ);
    assign bus_addr  = host_addr_r + {19'b0, xfer_count};
    assign bus_wen   = !load_r;
    assign bus_wdata = burst_buf;

    always_comb begin
        scratch_req   = '0;
        scratch_addr  = '0;
        scratch_wen   = '0;
        scratch_wdata = '0;

        if (state == S_SCRATCH_REQ || state == S_SCRATCH_WRITE) begin
            scratch_req[cur_bank] = 1'b1;
            scratch_addr[cur_bank*BANK_ADDR_W +: BANK_ADDR_W] = cur_offset;
            if (state == S_SCRATCH_WRITE) begin
                scratch_wen[cur_bank] = 1'b1;
                scratch_wdata[cur_bank*DATA_W +: DATA_W] = burst_buf[burst_idx*8 +: 8];
            end
        end
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state          <= S_IDLE;
            load_r         <= 1'b0;
            host_addr_r    <= '0;
            scratch_base_r <= '0;
            total_bytes_r  <= '0;
            xfer_count     <= '0;
            byte_counter   <= '0;
            burst_buf      <= '0;
            burst_idx      <= '0;
            burst_len_r    <= '0;
            read_bank_r    <= '0;
        end else begin
            case (state)
                S_IDLE: begin
                    if (cmd_valid) begin
                        load_r         <= cmd_load;
                        host_addr_r    <= cmd_host_addr;
                        scratch_base_r <= {
                            {(LOCAL_ADDR_W - SLOT_BITS - SLOT_ADDR_W){1'b0}},
                            cmd_slot_id,
                            {SLOT_ADDR_W{1'b0}}
                        };
                        total_bytes_r  <= cmd_byte_count;
                        xfer_count     <= '0;
                        byte_counter   <= '0;
                        burst_buf      <= '0;
                        burst_idx      <= '0;
                        burst_len_r    <= burst_len_for(cmd_byte_count);

                        if (cmd_byte_count == 13'd0 || cmd_byte_count > 13'd4096) begin
                            state <= S_ERROR;
                        end else if (cmd_load) begin
                            state <= S_BUS_REQ;
                        end else begin
                            state <= S_SCRATCH_REQ;
                        end
                    end
                end

                S_BUS_REQ: begin
                    if (bus_ack) begin
                        if (load_r) begin
                            burst_buf <= bus_rdata;
                            burst_idx <= '0;
                            state     <= S_SCRATCH_WRITE;
                        end else begin
                            byte_counter <= byte_counter + {27'd0, burst_len_r};
                            xfer_count   <= xfer_count + {8'd0, burst_len_r};

                            if (xfer_count + {8'd0, burst_len_r} >= total_bytes_r) begin
                                state <= S_DONE;
                            end else begin
                                burst_idx   <= '0;
                                burst_len_r <= burst_len_for(
                                    total_bytes_r - (xfer_count + {8'd0, burst_len_r})
                                );
                                burst_buf   <= '0;
                                state       <= S_SCRATCH_REQ;
                            end
                        end
                    end
                end

                S_SCRATCH_REQ: begin
                    if (scratch_grant[cur_bank]) begin
                        read_bank_r <= cur_bank;
                        state       <= S_SCRATCH_DATA;
                    end
                end

                S_SCRATCH_DATA: begin
                    burst_buf[burst_idx*8 +: 8] <= scratch_rdata[read_bank_r*DATA_W +: DATA_W];

                    if ({1'b0, burst_idx} + 5'd1 >= burst_len_r) begin
                        burst_idx <= '0;
                        state     <= S_BUS_REQ;
                    end else begin
                        burst_idx <= burst_idx + 4'd1;
                        state     <= S_SCRATCH_REQ;
                    end
                end

                S_SCRATCH_WRITE: begin
                    if (scratch_grant[cur_bank]) begin
                        if ({1'b0, burst_idx} + 5'd1 >= burst_len_r) begin
                            byte_counter <= byte_counter + {27'd0, burst_len_r};
                            xfer_count   <= xfer_count + {8'd0, burst_len_r};

                            if (xfer_count + {8'd0, burst_len_r} >= total_bytes_r) begin
                                state <= S_DONE;
                            end else begin
                                burst_idx   <= '0;
                                burst_len_r <= burst_len_for(
                                    total_bytes_r - (xfer_count + {8'd0, burst_len_r})
                                );
                                state <= S_BUS_REQ;
                            end
                        end else begin
                            burst_idx <= burst_idx + 4'd1;
                        end
                    end
                end

                S_DONE: begin
                    state <= S_IDLE;
                end

                S_ERROR: begin
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
