module dma_engine #(
    parameter int NUM_BANKS   = 8,
    parameter int BANK_ADDR_W = 14,
    parameter int DATA_W      = 8,
    parameter int SLOT_BITS   = 5
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

    typedef enum logic [2:0] {
        S_IDLE      = 3'd0,
        S_BUS_REQ   = 3'd1,
        S_BUS_WAIT  = 3'd2,
        S_SCRATCH   = 3'd3,
        S_DONE      = 3'd4,
        S_ERROR     = 3'd5
    } state_t;

    state_t state;

    logic        load_r;
    logic [31:0] host_addr_r;
    logic [16:0] scratch_base_r;
    logic [12:0] total_bytes_r;
    logic [12:0] xfer_count;

    logic [127:0] burst_buf;
    logic [3:0]   burst_idx;

    logic [16:0] scratch_byte_addr;
    assign scratch_byte_addr = scratch_base_r + {4'b0, xfer_count} + {13'b0, burst_idx};

    wire [2:0]             cur_bank   = scratch_byte_addr[16:14];
    wire [BANK_ADDR_W-1:0] cur_offset = scratch_byte_addr[BANK_ADDR_W-1:0];

    logic [31:0] byte_counter;
    assign bytes_moved = byte_counter;

    assign cmd_ready = (state == S_IDLE);
    assign done      = (state == S_DONE);
    assign error     = (state == S_ERROR);

    assign bus_req  = (state == S_BUS_WAIT) && !load_r;  // store: send to host
    assign bus_addr = host_addr_r + {19'b0, xfer_count};
    assign bus_wen  = !load_r;
    assign bus_wdata = burst_buf;

    // Scratchpad access -- only target the current bank
    always_comb begin
        scratch_req   = '0;
        scratch_addr  = '0;
        scratch_wen   = '0;
        scratch_wdata = '0;

        if (state == S_SCRATCH) begin
            scratch_req[cur_bank] = 1'b1;
            scratch_addr[cur_bank*BANK_ADDR_W +: BANK_ADDR_W] = cur_offset;
            if (load_r) begin
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
            burst_buf      <= '0;
            burst_idx      <= '0;
            byte_counter   <= '0;
        end else begin
            case (state)
                S_IDLE: begin
                    if (cmd_valid) begin
                        load_r         <= cmd_load;
                        host_addr_r    <= cmd_host_addr;
                        scratch_base_r <= {cmd_slot_id, 12'b0};
                        total_bytes_r  <= cmd_byte_count;
                        xfer_count     <= '0;
                        burst_idx      <= '0;
                        state          <= S_BUS_REQ;
                    end
                end

                S_BUS_REQ: begin
                    if (xfer_count >= total_bytes_r) begin
                        state <= S_DONE;
                    end else if (load_r) begin
                        state <= S_BUS_WAIT;
                    end else begin
                        burst_idx <= '0;
                        state     <= S_SCRATCH;
                    end
                end

                S_BUS_WAIT: begin
                    if (bus_ack) begin
                        if (load_r) begin
                            burst_buf <= bus_rdata;
                            burst_idx <= '0;
                            state     <= S_SCRATCH;
                        end else begin
                            xfer_count   <= xfer_count + 13'd16;
                            byte_counter <= byte_counter + 32'd16;
                            state        <= S_BUS_REQ;
                        end
                    end
                end

                S_SCRATCH: begin
                    if (scratch_grant[cur_bank]) begin
                        if (load_r) begin
                            if (burst_idx == 4'd15 ||
                                xfer_count + {9'b0, burst_idx} >= total_bytes_r - 13'd1) begin
                                xfer_count   <= xfer_count + {9'b0, burst_idx} + 13'd1;
                                byte_counter <= byte_counter + {28'b0, burst_idx} + 32'd1;
                                state        <= S_BUS_REQ;
                            end else begin
                                burst_idx <= burst_idx + 4'd1;
                            end
                        end else begin
                            burst_buf[burst_idx*8 +: 8] <=
                                scratch_rdata[cur_bank*DATA_W +: DATA_W];
                            if (burst_idx == 4'd15 ||
                                xfer_count + {9'b0, burst_idx} >= total_bytes_r - 13'd1) begin
                                xfer_count   <= xfer_count + {9'b0, burst_idx} + 13'd1;
                                byte_counter <= byte_counter + {28'b0, burst_idx} + 32'd1;
                                state        <= S_BUS_WAIT;
                            end else begin
                                burst_idx <= burst_idx + 4'd1;
                            end
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
