module isa_decoder_formal;
    (* gclk *) logic clk;

    logic rst_n;
    logic f_past_valid;

    (* anyseq *) logic        desc_valid;
    (* anyseq *) logic [63:0] desc_data;
    (* anyseq *) logic [7:0]  default_m;
    (* anyseq *) logic [7:0]  default_n;
    (* anyseq *) logic [7:0]  default_k;
    (* anyseq *) logic        fault_clear;

    logic        desc_consumed;
    logic        action_valid;
    logic        action_ready;
    logic [2:0]  action_type;
    logic        action_load;
    logic [4:0]  action_src_slot;
    logic [4:0]  action_dst_slot;
    logic [7:0]  action_dim_m;
    logic [7:0]  action_dim_n;
    logic [7:0]  action_dim_k;
    logic [7:0]  action_flags;
    logic [3:0]  action_tag;
    logic        fault_valid;
    logic [1:0]  fault_cause;
    logic [63:0] fault_descriptor;
    logic        fault_active;

    initial f_past_valid = 1'b0;

    always_ff @(posedge clk) begin
        f_past_valid <= 1'b1;
    end

    assign rst_n = f_past_valid;
    assign action_ready = 1'b1;

    isa_decoder dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .desc_valid       (desc_valid),
        .desc_data        (desc_data),
        .desc_consumed    (desc_consumed),
        .default_m        (default_m),
        .default_n        (default_n),
        .default_k        (default_k),
        .action_valid     (action_valid),
        .action_ready     (action_ready),
        .action_type      (action_type),
        .action_load      (action_load),
        .action_src_slot  (action_src_slot),
        .action_dst_slot  (action_dst_slot),
        .action_dim_m     (action_dim_m),
        .action_dim_n     (action_dim_n),
        .action_dim_k     (action_dim_k),
        .action_flags     (action_flags),
        .action_tag       (action_tag),
        .fault_valid      (fault_valid),
        .fault_cause      (fault_cause),
        .fault_descriptor (fault_descriptor),
        .fault_clear      (fault_clear),
        .fault_active     (fault_active)
    );

    isa_decoder_props props (
        .clk            (clk),
        .rst_n          (rst_n),
        .desc_valid     (desc_valid),
        .desc_data      (desc_data),
        .desc_consumed  (desc_consumed),
        .action_valid   (action_valid),
        .action_ready   (action_ready),
        .action_type    (action_type),
        .fault_valid    (fault_valid),
        .fault_active   (fault_active),
        .fault_clear    (fault_clear)
    );

    logic _unused;
    assign _unused = &{1'b0, action_load, action_src_slot, action_dst_slot,
                       action_dim_m, action_dim_n, action_dim_k,
                       action_flags, action_tag, fault_cause, fault_descriptor};
endmodule
