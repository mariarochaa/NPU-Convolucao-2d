
`timescale 1ns / 1ps

// =========================================================================
// MÓDULO: mac_q8_8_img (Multiplicador-Acumulador Corrigido)
// =========================================================================
module mac_q8_8_img (
    input wire        clk,
    input wire        rst_n,
    input wire        clear,       // Sinaliza o início de uma nova janela 2x2
    input wire        en,          // Habilita a acumulação dos pixels restantes
    input wire [15:0] pixel,       // Unsigned Q8.8 (0.0 a 255.996)
    input wire [15:0] coeff,       // Signed Q8.8 (-128.0 a 127.996)
    output reg [15:0] final_pixel  // Saída final truncada e saturada em Q8.8
);

    // Registrador interno de alta precisão (formato Q16.16)
    reg signed [31:0] accum;
    
    // Multiplicação mista estendendo o pixel (unsigned) para positivo assinado
    wire signed [31:0] prod = $signed({1'b0, pixel}) * $signed(coeff);

    // Lógica do Acumulador Sequencial
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            accum <= 32'sd0;
        end else if (clear) begin
            // CORREÇÃO: Em vez de zerar puro, inicia o acumulador com o primeiro produto (P00)
            accum <= prod; 
        end else if (en) begin
            accum <= accum + prod; // Acumula os demais produtos (P01, P10, P11)
        end
    end

    // Lógica Combinacional de Saturação utilizando casts explícitos de sinal
    always @(*) begin
        // 32'h007FFF00 representa +127.996 em Q16.16
        if (accum > $signed(32'h007FFF00)) begin
            final_pixel = 16'h7FFF; // Satura no limite máximo positivo
            
        // 32'hFF800000 representa -128.0 em Q16.16
        end else if (accum < $signed(32'hFF800000)) begin
            final_pixel = 16'h8000; // Satura no limite mínimo negativo
            
        end else begin
            final_pixel = accum[23:8]; // Operação normal: retira a fração extra (truncamento)
        end
    end

endmodule


// =========================================================================
// MÓDULO: conv2d_2x2_controller
// =========================================================================
module conv2d_2x2_controller #(
    parameter IMG_WIDTH = 640
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [15:0] pixel_in,   
    input  wire        pixel_vld,  
    
    output reg  [15:0] mac_pixel,
    output reg  [15:0] mac_coeff,
    output reg         mac_en,
    output reg         mac_clear,
    output reg         data_ready  
);

    // Memória de linha (Line Buffer) para o atraso vertical da imagem
    reg [15:0] line_buffer [0:IMG_WIDTH-1];
    reg [$clog2(IMG_WIDTH)-1:0] wr_ptr;

    // Registradores que formam a matriz/janela local de 2x2 pixels
    reg [15:0] p00, p01, p10, p11; 
    
    // Estados da FSM de controle
    reg [2:0] state;
    localparam IDLE = 0, P00 = 1, P01 = 2, P10 = 3, P11 = 4, DONE = 5;

    // Constantes do Kernel (Filtro Blur/Média: 0.25 em Q8.8 = 16'h0040)
    wire [15:0] K [0:3];
    assign K[0] = 16'h0040; 
    assign K[1] = 16'h0040;
    assign K[2] = 16'h0040;
    assign K[3] = 16'h0040;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr     <= 0;
            state      <= IDLE;
            mac_pixel  <= 16'h0;
            mac_coeff  <= 16'h0;
            mac_en     <= 1'b0;
            mac_clear  <= 1'b0;
            data_ready <= 1'b0;
            p00 <= 0; p01 <= 0; p10 <= 0; p11 <= 0;
        end else if (pixel_vld) begin
            // Deslocamento horizontal e vertical da janela de pixels
            p11 <= pixel_in;
            p10 <= p11;
            p01 <= line_buffer[wr_ptr];
            p00 <= p01;
            
            // Atualiza o buffer com o pixel que acabou de chegar
            line_buffer[wr_ptr] <= pixel_in;
            wr_ptr <= (wr_ptr == IMG_WIDTH-1) ? 0 : wr_ptr + 1;
            
            // Salta diretamente para o processamento do primeiro pixel
            state      <= P00;
            data_ready <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    mac_en     <= 1'b0;
                    mac_clear  <= 1'b0;
                    data_ready <= 1'b0;
                end
                P00: begin 
                    mac_clear  <= 1'b1; // Ativa o sinal clear para reiniciar o acumulador interno
                    mac_en     <= 1'b0; // Opcional, clear tem preferência na nova lógica do MAC
                    mac_pixel  <= p00; 
                    mac_coeff  <= K[0]; 
                    state      <= P01; 
                end
                P01: begin 
                    mac_clear  <= 1'b0; 
                    mac_en     <= 1'b1; // Habilita soma contínua
                    mac_pixel  <= p01; 
                    mac_coeff  <= K[1]; 
                    state      <= P10; 
                end
                P10: begin 
                    mac_clear  <= 1'b0; 
                    mac_en     <= 1'b1; 
                    mac_pixel  <= p10; 
                    mac_coeff  <= K[2]; 
                    state      <= P11; 
                end
                P11: begin 
                    mac_clear  <= 1'b0; 
                    mac_en     <= 1'b1; 
                    mac_pixel  <= p11; 
                    mac_coeff  <= K[3]; 
                    state      <= DONE; 
                end
                DONE: begin 
                    mac_en     <= 1'b0; 
                    data_ready <= 1'b1; // Pulsa a flag indicando dado pronto na saída do sistema
                    state      <= IDLE; 
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule


// =========================================================================
// MÓDULO: conv2d_2x2_top (Top-Level)
// =========================================================================
module conv2d_2x2_top #(
    parameter IMG_WIDTH = 640
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [15:0] pixel_in,   
    input  wire        pixel_vld,  
    output wire [15:0] final_pixel, 
    output wire        data_ready  
);

    wire [15:0] w_mac_pixel;
    wire [15:0] w_mac_coeff;
    wire        w_mac_en;
    wire        w_mac_clear;

    conv2d_2x2_controller #(
        .IMG_WIDTH(IMG_WIDTH)
    ) controller_u0 (
        .clk(clk),
        .rst_n(rst_n),
        .pixel_in(pixel_in),
        .pixel_vld(pixel_vld),
        .mac_pixel(w_mac_pixel),
        .mac_coeff(w_mac_coeff),
        .mac_en(w_mac_en),
        .mac_clear(w_mac_clear),
        .data_ready(data_ready)
    );

    mac_q8_8_img mac_u0 (
        .clk(clk),
        .rst_n(rst_n),
        .clear(w_mac_clear),
        .en(w_mac_en),
        .pixel(w_mac_pixel),
        .coeff(w_mac_coeff),
        .final_pixel(final_pixel)
    );

endmodule


// =========================================================================
// MÓDULO: conv2d_2x2_top_tb (Testbench)
// =========================================================================
module conv2d_2x2_top_tb();

    reg         clk;
    reg         rst_n;
    reg  [15:0] pixel_in;
    reg         pixel_vld;
    wire [15:0] final_pixel;
    wire        data_ready;

    localparam TEST_WIDTH = 4;
    
    conv2d_2x2_top #(
        .IMG_WIDTH(TEST_WIDTH)
    ) uut (
        .clk(clk),
        .rst_n(rst_n),
        .pixel_in(pixel_in),
        .pixel_vld(pixel_vld),
        .final_pixel(final_pixel),
        .data_ready(data_ready)
    );

    always #5 clk = ~clk;

    integer idx;

    task send_pixel(input [15:0] val);
        begin
            pixel_in  = val;
            pixel_vld = 1;
            @(posedge clk);
            pixel_vld = 0;
            @(posedge data_ready);
            #1; 
        end
    endtask

    initial begin
        clk       = 0;
        rst_n     = 0;
        pixel_in  = 16'h0;
        pixel_vld = 0;

        for (idx = 0; idx < TEST_WIDTH; idx = idx + 1) begin
            uut.controller_u0.line_buffer[idx] = 16'h0000;
        end

        #20;
        rst_n = 1; 
        #20;

        $display("==========================================================================");
        $display(" Começando o Teste do Sistema de Convolucao 2x2 ");
        $display(" Configuração da Largura de Linha para o Teste: %0d pixels", TEST_WIDTH);
        $display("==========================================================================");

        $display("\n[PASSO 1] Alimentando a Linha 0 da Imagem...");
        send_pixel(16'h4000); // (0,0) = 64.0 em Q8.8
        send_pixel(16'h4000); // (0,1)
        send_pixel(16'h4000); // (0,2)
        send_pixel(16'h4000); // (0,3)

        $display("\n[PASSO 2] Alimentando a Linha 1 (Calculando Janela)...");
        send_pixel(16'h4000); // (1,0)
        send_pixel(16'h4000); // (1,1) -> Janela perfeitamente cheia com 16'h4000
        
        if (final_pixel == 16'h4000)
            $display("  [PASS] Filtro de Média Calculado com Sucesso: Saída = %h (64.0)", final_pixel);
        else
            $error("  [FAIL] Erro no cálculo: Obtido %h", final_pixel);

        $display("\n[PASSO 3] Forçando condições de estouro (Saturação)...");
        send_pixel(16'hC800); // (1,2) = 200.0 em Q8.8
        send_pixel(16'hC800); // (1,3)
        send_pixel(16'hC800); // (2,0)
        send_pixel(16'hC800); // (2,1) -> Janela completamente cheia com 200.0 (Média teórica = 200.0)
        
        // Como o limite máximo do formato Q8.8 com sinal é +127.996 (16'h7FFF), deve saturar.
        if (final_pixel == 16'h7FFF)
            $display("  [PASS] O circuito saturou perfeitamente em +127.99 (16'h7FFF)");
        else
            $error("  [FAIL] Falha no bloco de saturação: Obtido %h", final_pixel);

        $display("\n==========================================================================");
        $display(" Simulação Concluída!");
        $display("==========================================================================");
        $stop;
    end

endmodule