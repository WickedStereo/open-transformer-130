module perf_counters (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        soft_reset,

    // Increment pulses
    input  logic        busy_inc,
    input  logic        stall_inc,
    input  logic [31:0] dma_bytes_inc,
    input  logic        dma_bytes_valid,
    input  logic        tile_inc,

    // Counter outputs
    output logic [31:0] busy_cycles,
    output logic [31:0] stall_cycles,
    output logic [31:0] dma_bytes,
    output logic [31:0] tile_count
);

    // Saturating increment helper
    function automatic [31:0] sat_add(input [31:0] counter, input [31:0] addend);
        logic [32:0] wide;
        begin
            wide = {1'b0, counter} + {1'b0, addend};
            if (wide[32])
                sat_add = 32'hFFFFFFFF;
            else
                sat_add = wide[31:0];
        end
    endfunction

    always_ff @(posedge clk) begin
        if (!rst_n || soft_reset) begin
            busy_cycles  <= '0;
            stall_cycles <= '0;
            dma_bytes    <= '0;
            tile_count   <= '0;
        end else begin
            if (busy_inc)
                busy_cycles <= sat_add(busy_cycles, 32'd1);
            if (stall_inc)
                stall_cycles <= sat_add(stall_cycles, 32'd1);
            if (dma_bytes_valid)
                dma_bytes <= sat_add(dma_bytes, dma_bytes_inc);
            if (tile_inc)
                tile_count <= sat_add(tile_count, 32'd1);
        end
    end

endmodule
