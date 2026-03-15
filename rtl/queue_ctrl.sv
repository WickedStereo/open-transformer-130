module queue_ctrl (
    input  logic        clk,
    input  logic        rst_n,

    // Configuration from MMIO
    input  logic [31:0] queue_base,
    input  logic [3:0]  queue_size_log2,
    input  logic [7:0]  head,
    output logic [7:0]  tail,
    input  logic        fault_halt,
    input  logic        enable,

    // Descriptor output to decoder
    output logic        desc_valid,
    output logic [63:0] desc_data,
    input  logic        desc_consumed,

    // Host bus (descriptor fetch)
    output logic        bus_req,
    output logic [31:0] bus_addr,
    input  logic [63:0] bus_rdata,
    input  logic        bus_ack
);

    typedef enum logic [1:0] {
        S_IDLE    = 2'd0,
        S_FETCH   = 2'd1,
        S_PRESENT = 2'd2
    } state_t;

    state_t state;

    // Queue depth mask for power-of-2 wrapping
    wire [7:0] depth_mask = (8'd1 << queue_size_log2) - 8'd1;
    wire queue_empty = (tail == head);

    // Fetch address: base + tail * 8 (each descriptor is 8 bytes)
    wire [31:0] fetch_addr = queue_base + {21'b0, tail & depth_mask, 3'b0};

    assign bus_req  = (state == S_FETCH);
    assign bus_addr = fetch_addr;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state      <= S_IDLE;
            tail       <= '0;
            desc_valid <= 1'b0;
            desc_data  <= '0;
        end else begin
            case (state)
                S_IDLE: begin
                    if (!queue_empty && !fault_halt && enable) begin
                        state <= S_FETCH;
                    end
                end

                S_FETCH: begin
                    if (bus_ack) begin
                        desc_data  <= bus_rdata;
                        desc_valid <= 1'b1;
                        state      <= S_PRESENT;
                    end
                end

                S_PRESENT: begin
                    if (desc_consumed) begin
                        desc_valid <= 1'b0;
                        tail       <= (tail + 8'd1) & depth_mask;
                        state      <= S_IDLE;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
