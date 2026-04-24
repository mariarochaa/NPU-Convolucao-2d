

module conv2d_2x2_controller #(
    parameter IMG_WIDTH = 640 // Largura da imagem em pixels
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [15:0] pixel_in,   // Pixel chegando da memória/sensor
    input  wire        pixel_vld,  // Sinal que um novo pixel está na entrada
    
    // Interface com o MAC
    output reg  [15:0] mac_pixel,
    output reg  [15:0] mac_coeff,
    output reg         mac_en,
    output reg         mac_clear,
    input  wire [15:0] final_pixel // Resultado vindo do MAC
);

    // --- 1. Line Buffer (FIFO) ---
    // Armazena uma linha inteira para podermos acessar a linha de cima
    reg [15:0] line_buffer [0:IMG_WIDTH-1];
    reg [$clog2(IMG_WIDTH)-1:0] wr_ptr, rd_ptr;
    wire [15:0] top_pixel;

    // --- 2. Registradores da Janela ---
    reg [15:0] p00, p01, p10, p11; // Janela 2x2
    
    // --- 3. Máquina de Estados para o MAC ---
    // Como o MAC é sequencial, precisamos de um mini-estado para enviar os 4 pixels
    reg [2:0] state;
    localparam IDLE = 0, P00 = 1, P01 = 2, P10 = 3, P11 = 4, DONE = 5;

    // Coeficientes do Kernel (Exemplo: Filtro de Média/Blur)
    // Em um projeto real, isso viria de uma ROM ou registradores
    wire [15:0] K [0:3];
    assign K[0] = 16'h0040; // 0.25 em Q8.8
    assign K[1] = 16'h0040;
    assign K[2] = 16'h0040;
    assign K[3] = 16'h0040;

    // Lógica do Line Buffer e Janela
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= 0;
            state <= IDLE;
        end else if (pixel_vld) begin
            // Move a janela
            p11 <= pixel_in;
            p10 <= p11;
            p01 <= line_buffer[wr_ptr];
            p00 <= p01;
            
            // Salva o pixel atual no buffer para a próxima linha
            line_buffer[wr_ptr] <= pixel_in;
            wr_ptr <= (wr_ptr == IMG_WIDTH-1) ? 0 : wr_ptr + 1;
            
            // Inicia o ciclo do MAC
            state <= P00;
        end else begin
            // Sequenciador do MAC
            case (state)
                P00: begin mac_clear <= 1; mac_en <= 1; mac_pixel <= p00; mac_coeff <= K[0]; state <= P01; end
                P01: begin mac_clear <= 0; mac_en <= 1; mac_pixel <= p01; mac_coeff <= K[1]; state <= P10; end
                P10: begin mac_clear <= 0; mac_en <= 1; mac_pixel <= p10; mac_coeff <= K[2]; state <= P11; end
                P11: begin mac_clear <= 0; mac_en <= 1; mac_pixel <= p11; mac_coeff <= K[3]; state <= P11; state <= DONE; end
                DONE: begin mac_en <= 0; state <= IDLE; end
            endcase
        end
    end
endmodule


//O Conceito do Line Buffer (Janela 2x2)Imagine a imagem vindo pixel a pixel. Para processar um quadrado 2x2, 
//você precisa do:Pixel atual ($P_{1,1}$)Pixel da esquerda ($P_{1,0}$) -> Basta um registrador.Pixel de cima ($P_{0,1}$) 
//-> Aqui entra o Line Buffer (FIFO).Pixel de cima-esquerda ($P_{0,0}$) -> Saída do Line Buffer + um registrador.



//Line Buffer Manual: Usei um array line_buffer. Em FPGAs de verdade (Xilinx/Intel), 
//o compilador vai converter isso automaticamente em Block RAM (BRAM). 
//Se a imagem for muito larga (ex: 1920p), cuidado para não estourar a memória da sua FPGA.

//O "Deslize" da Janela: A cada novo pixel que chega (pixel_vld), nós empurramos os pixels para o lado e para baixo. 
//É como se estivéssemos arrastando uma lupa 2x2 pela imagem.

//Sequenciamento: O MAC que fizemos precisa de 4 ciclos para terminar uma janela 2x2. 
//Por isso, a máquina de estados (P00 até DONE) envia um par de dados por ciclo de clock assim que a janela é atualizada.