module mmio_regs (
    input  logic        clk,
    input  logic        rst_n,

    // Host-facing MMIO port
    input  logic [5:0]  mmio_addr,
    input  logic        mmio_wen,
    input  logic [31:0] mmio_wdata,
    output logic [31:0] mmio_rdata,
    input  logic        mmio_valid,
    output logic        mmio_ready,

    // Configuration outputs
    output logic        ctrl_enable,
    output logic        ctrl_soft_reset,
    output logic        ctrl_fault_clear,
    output logic [31:0] queue_base,
    output logic [3:0]  queue_size_log2,
    output logic [7:0]  cmd_head,
    output logic [7:0]  tile_default_m,
    output logic [7:0]  tile_default_n,
    output logic [7:0]  tile_default_k,
    output logic [31:0] dma_host_addr,
    output logic [31:0] scratch_base,

    // Status inputs
    input  logic [7:0]  cmd_tail,
    input  logic        status_busy,
    input  logic        status_fault,
    input  logic        status_dma_active,
    input  logic        status_compute_active,
    input  logic [3:0]  status_queue_depth,
    input  logic [63:0] fault_info_desc,
    input  logic [7:0]  fault_info_opcode,
    input  logic [1:0]  fault_info_cause,

    // Performance counter inputs
    input  logic [31:0] perf_busy_cycles,
    input  logic [31:0] perf_stall_cycles,
    input  logic [31:0] perf_dma_bytes,
    input  logic [31:0] perf_tile_count
);

    // ── Register offsets (byte address, bits [5:2] select register) ──
    localparam REG_CTRL           = 4'h0;   // 0x00
    localparam REG_STATUS         = 4'h1;   // 0x04
    localparam REG_QUEUE_BASE     = 4'h2;   // 0x08
    localparam REG_QUEUE_SIZE     = 4'h3;   // 0x0C
    localparam REG_CMD_HEAD       = 4'h4;   // 0x10
    localparam REG_CMD_TAIL       = 4'h5;   // 0x14
    localparam REG_FAULT_INFO     = 4'h6;   // 0x18
    localparam REG_DEFAULT_M      = 4'h7;   // 0x1C
    localparam REG_DEFAULT_N      = 4'h8;   // 0x20
    localparam REG_DEFAULT_K      = 4'h9;   // 0x24
    localparam REG_PERF_BUSY      = 4'hA;   // 0x28
    localparam REG_PERF_STALL     = 4'hB;   // 0x2C
    localparam REG_PERF_DMA       = 4'hC;   // 0x30
    localparam REG_PERF_TILE      = 4'hD;   // 0x34
    localparam REG_DMA_HOST_ADDR  = 4'hE;   // 0x38
    localparam REG_SCRATCH_BASE   = 4'hF;   // 0x3C

    wire [3:0] reg_sel = mmio_addr[5:2];

    // ── CTRL register bits ──
    logic [31:0] ctrl_reg;
    assign ctrl_enable     = ctrl_reg[0];
    // soft_reset and fault_clear are self-clearing pulses
    logic soft_reset_pending, fault_clear_pending;
    assign ctrl_soft_reset  = soft_reset_pending;
    assign ctrl_fault_clear = fault_clear_pending;

    // ── RW register storage ──
    logic [31:0] queue_base_reg;
    logic [3:0]  queue_size_reg;
    logic [7:0]  head_reg;
    logic [7:0]  default_m_reg, default_n_reg, default_k_reg;
    logic [31:0] dma_host_addr_reg;
    logic [31:0] scratch_base_reg;

    assign queue_base     = queue_base_reg;
    assign queue_size_log2 = queue_size_reg;
    assign cmd_head       = head_reg;
    assign tile_default_m = default_m_reg;
    assign tile_default_n = default_n_reg;
    assign tile_default_k = default_k_reg;
    assign dma_host_addr  = dma_host_addr_reg;
    assign scratch_base   = scratch_base_reg;

    // Single-cycle ready
    assign mmio_ready = mmio_valid;

    // ── Read mux ──
    always_comb begin
        mmio_rdata = 32'd0;
        case (reg_sel)
            REG_CTRL:          mmio_rdata = ctrl_reg;
            REG_STATUS:        mmio_rdata = {24'd0, status_queue_depth,
                                             status_compute_active, status_dma_active,
                                             status_fault, status_busy};
            REG_QUEUE_BASE:    mmio_rdata = queue_base_reg;
            REG_QUEUE_SIZE:    mmio_rdata = {28'd0, queue_size_reg};
            REG_CMD_HEAD:      mmio_rdata = {24'd0, head_reg};
            REG_CMD_TAIL:      mmio_rdata = {24'd0, cmd_tail};
            REG_FAULT_INFO:    mmio_rdata = {20'd0, fault_info_cause,
                                             fault_info_opcode, 2'b00};
            REG_DEFAULT_M:     mmio_rdata = {24'd0, default_m_reg};
            REG_DEFAULT_N:     mmio_rdata = {24'd0, default_n_reg};
            REG_DEFAULT_K:     mmio_rdata = {24'd0, default_k_reg};
            REG_PERF_BUSY:     mmio_rdata = perf_busy_cycles;
            REG_PERF_STALL:    mmio_rdata = perf_stall_cycles;
            REG_PERF_DMA:      mmio_rdata = perf_dma_bytes;
            REG_PERF_TILE:     mmio_rdata = perf_tile_count;
            REG_DMA_HOST_ADDR: mmio_rdata = dma_host_addr_reg;
            REG_SCRATCH_BASE:  mmio_rdata = scratch_base_reg;
        endcase
    end

    // ── Write logic ──
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            ctrl_reg           <= '0;
            soft_reset_pending <= 1'b0;
            fault_clear_pending<= 1'b0;
            queue_base_reg     <= '0;
            queue_size_reg     <= '0;
            head_reg           <= '0;
            default_m_reg      <= 8'd64;
            default_n_reg      <= 8'd64;
            default_k_reg      <= 8'd64;
            dma_host_addr_reg  <= '0;
            scratch_base_reg   <= '0;
        end else begin
            // Self-clearing pulses decay after one cycle
            soft_reset_pending  <= 1'b0;
            fault_clear_pending <= 1'b0;

            if (mmio_valid && mmio_wen) begin
                case (reg_sel)
                    REG_CTRL: begin
                        ctrl_reg <= mmio_wdata;
                        if (mmio_wdata[1]) soft_reset_pending  <= 1'b1;
                        if (mmio_wdata[2]) fault_clear_pending <= 1'b1;
                    end
                    REG_QUEUE_BASE:    queue_base_reg    <= mmio_wdata;
                    REG_QUEUE_SIZE:    queue_size_reg    <= mmio_wdata[3:0];
                    REG_CMD_HEAD:      head_reg          <= mmio_wdata[7:0];
                    REG_DEFAULT_M:     default_m_reg     <= mmio_wdata[7:0];
                    REG_DEFAULT_N:     default_n_reg     <= mmio_wdata[7:0];
                    REG_DEFAULT_K:     default_k_reg     <= mmio_wdata[7:0];
                    REG_DMA_HOST_ADDR: dma_host_addr_reg <= mmio_wdata;
                    REG_SCRATCH_BASE:  scratch_base_reg  <= mmio_wdata;
                    default: ; // Read-only or reserved
                endcase
            end

            // Soft reset clears all registers to defaults
            if (soft_reset_pending) begin
                ctrl_reg          <= '0;
                queue_base_reg    <= '0;
                queue_size_reg    <= '0;
                head_reg          <= '0;
                default_m_reg     <= 8'd64;
                default_n_reg     <= 8'd64;
                default_k_reg     <= 8'd64;
                dma_host_addr_reg <= '0;
                scratch_base_reg  <= '0;
            end
        end
    end

    logic _unused;
    assign _unused = &{1'b0, fault_info_desc, mmio_addr[1:0]};

endmodule
