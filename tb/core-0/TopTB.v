`timescale 1ns/1ps

module tb_conv2d_from_hex;
    reg clk;
    reg rst_n;

    // ROM
    wire [9:0] rom_addr;
    wire [7:0] rom_data;

    // Feeder → controlador
    wire [15:0] pixel_stream;
    wire        pixel_vld;
    wire        frame_done;

    // Controlador → MAC
    wire [15:0] mac_pixel, mac_coeff;
    wire        mac_en, mac_clear;
    wire [15:0] final_pixel;

    // Clock
    initial clk = 0;
    always #5 clk = ~clk;

    // Instancia ROM (já com $readmemh do mnist_data.hex)
    image_rom u_rom (
        .clk     (clk),
        .addr    (rom_addr),
        .data_out(rom_data)
    );

    // Feeder 28x28
    image_feeder_28x28 u_feeder (
        .clk      (clk),
        .rst_n    (rst_n),
        .rom_addr (rom_addr),
        .rom_data (rom_data),
        .pixel_out(pixel_stream),
        .pixel_vld(pixel_vld),
        .frame_done(frame_done)
    );

    // Controlador 2x2
    conv2d_2x2_controller #(
        .IMG_WIDTH(28)
    ) u_ctrl (
        .clk       (clk),
        .rst_n     (rst_n),
        .pixel_in  (pixel_stream),
        .pixel_vld (pixel_vld),
        .mac_pixel (mac_pixel),
        .mac_coeff (mac_coeff),
        .mac_en    (mac_en),
        .mac_clear (mac_clear),
        .final_pixel(final_pixel)
    );

    // MAC Q8.8 (use um dos seus, ex: mac_q8_8_img)
    mac_q8_8_img u_mac (
        .clk        (clk),
        .rst_n      (rst_n),
        .clear      (mac_clear),
        .en         (mac_en),
        .pixel      (mac_pixel),
        .coeff      (mac_coeff),
        .final_pixel(final_pixel)
    );

    // Sequência de reset e simulação
    initial begin
        rst_n = 0;
        #40;
        rst_n = 1;

        // roda até terminar o frame
        wait(frame_done);
        #2000;  // dá tempo para terminar últimas janelas
    end
endmodule