module isa_decoder_props (
    input logic        clk,
    input logic        rst_n,
    input logic        desc_valid,
    input logic [63:0] desc_data,
    input logic        desc_consumed,
    input logic        action_valid,
    input logic        action_ready,
    input logic [2:0]  action_type,
    input logic        fault_valid,
    input logic        fault_active,
    input logic        fault_clear
);

    wire [7:0] opcode  = desc_data[63:56];
    wire [3:0] reserved = desc_data[3:0];
    wire [7:0] dst_raw = desc_data[47:40];
    wire [7:0] src_raw = desc_data[39:32];

    // P1: Invalid opcode (> 0x07) always produces a fault
    property p_invalid_opcode_faults;
        @(posedge clk) disable iff (!rst_n)
            (desc_valid && !fault_active && opcode > 8'h07 && reserved == 4'd0)
            |-> ##[1:3] fault_active;
    endproperty
    assert property (p_invalid_opcode_faults)
        else $error("FORMAL: invalid opcode did not produce fault");

    // P2: Reserved field nonzero always produces a fault
    property p_reserved_field_faults;
        @(posedge clk) disable iff (!rst_n)
            (desc_valid && !fault_active && reserved != 4'd0)
            |-> ##[1:3] fault_active;
    endproperty
    assert property (p_reserved_field_faults)
        else $error("FORMAL: reserved field nonzero did not produce fault");

    // P3: fault_active blocks new decodes (no action_valid while faulted)
    property p_fault_blocks_decode;
        @(posedge clk) disable iff (!rst_n)
            fault_active |-> !action_valid;
    endproperty

    // P4: fault_clear deasserts fault_active
    property p_fault_clear_works;
        @(posedge clk) disable iff (!rst_n)
            (fault_active && fault_clear) |=> !fault_active;
    endproperty
    assert property (p_fault_clear_works)
        else $error("FORMAL: fault_clear did not deassert fault_active");

    // P5: desc_consumed is a one-cycle pulse
    property p_consumed_pulse;
        @(posedge clk) disable iff (!rst_n)
            desc_consumed |=> !desc_consumed;
    endproperty
    assert property (p_consumed_pulse)
        else $error("FORMAL: desc_consumed held for more than one cycle");

    // P6: Valid opcode with valid descriptor produces action (no fault)
    property p_valid_opcode_no_fault;
        @(posedge clk) disable iff (!rst_n)
            (desc_valid && !fault_active && opcode <= 8'h07 && reserved == 4'd0
             && dst_raw < 8'd32 && src_raw < 8'd32)
            |-> ##[1:3] (action_valid || desc_consumed);
    endproperty

endmodule
