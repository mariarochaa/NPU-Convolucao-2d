module image_feeder_28x28 (
    input  wire       clk,
    input  wire       rst_n,
    // interface com ROM 8 bits
    output reg  [9:0] rom_addr,
    input  wire [7:0] rom_data,
    // interface de saída para o controlador
    output reg  [15:0] pixel_out,   // Q8.8
    output reg         pixel_vld,
    output reg         frame_done
);
    localparam NUM_PIXELS = 28*28;  // 784

    reg [9:0] count;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rom_addr   <= 0;
            count      <= 0;
            pixel_out  <= 16'd0;
            pixel_vld  <= 1'b0;
            frame_done <= 1'b0;
        end else begin
            if (!frame_done) begin
                // 1 ciclo por pixel
                pixel_out <= {rom_data, 8'b0}; // 8-bit → Q8.8
                pixel_vld <= 1'b1;

                rom_addr <= rom_addr + 1;
                count    <= count + 1;

                if (count == NUM_PIXELS-1) begin
                    frame_done <= 1'b1;
                end
            end else begin
                pixel_vld <= 1'b0;
            end
        end
    end
endmodule