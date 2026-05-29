// ROM de imagem inicializada via $readmemh
module image_rom (
    input  wire       clk,
    input  wire [9:0] addr,
    output reg  [7:0] data_out
);
    // 28x28 = 784 pixels
    reg [7:0] memory [0:783];

    initial begin
        // Arquivo gerado pelo script Python
        $readmemh("C:/CI/NPU-Convolucao-2d/rtl/Core-0/mnist_data.hex", memory);
    end

    always @(posedge clk) begin
        data_out <= memory[addr];
    end
endmodule