module icebreaker_demo_top (
    input  logic       clk_12mhz,
    input  logic       btn_n,
    output logic [4:0] leds
);
    logic        demo_started;
    logic        demo_done;
    logic        demo_pass;
    logic        demo_fault;
    logic [31:0] status_snapshot;
    logic [7:0]  tail_snapshot;
    logic [31:0] output_word;
    logic [23:0] heartbeat_div;

    fpga_attention_demo u_demo (
        .clk            (clk_12mhz),
        .btn_n          (btn_n),
        .demo_started   (demo_started),
        .demo_done      (demo_done),
        .demo_pass      (demo_pass),
        .demo_fault     (demo_fault),
        .status_snapshot(status_snapshot),
        .tail_snapshot  (tail_snapshot),
        .output_word    (output_word)
    );

    always_ff @(posedge clk_12mhz or negedge btn_n) begin
        if (!btn_n)
            heartbeat_div <= '0;
        else
            heartbeat_div <= heartbeat_div + 24'd1;
    end

    assign leds[0] = heartbeat_div[23];
    assign leds[1] = demo_started;
    assign leds[2] = demo_done;
    assign leds[3] = demo_pass;
    assign leds[4] = demo_fault;

    logic _unused;
    assign _unused = &{1'b0, status_snapshot, tail_snapshot, output_word};
endmodule
