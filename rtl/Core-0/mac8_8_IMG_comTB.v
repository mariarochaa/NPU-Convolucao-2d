
`timescale 1ns / 1ps

module mac_q8_8_img (
    input  wire        clk,
    input  wire        rst_n,       // Reset assíncrono ativo baixo
    input  wire        clear,       // Zera o acumulador para nova janela
    input  wire        en,          // Habilita a soma do produto atual
    input  wire [15:0] pixel,       // Entrada Q8.8 (com sinal)
    input  wire [15:0] coeff,       // Coeficiente Q8.8 (com sinal)
    output reg  [15:0] final_pixel  // Saída saturada Q8.8
);

    // --- Lógica Interna ---
    // Multiplicação Q8.8 x Q8.8 resulta em Q16.16 (32 bits)
    // Usamos um acumulador de 32 bits para manter a precisão total durante as somas
    reg  signed [31:0] acc;
    wire signed [31:0] product;

    // Multiplicação com sinal (complemento de 2)
    assign product = $signed(pixel) * $signed(coeff);

    // --- Acumulador ---
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc <= 32'sd0;
        end else if (clear) begin
            acc <= 32'sd0;
        end else if (en) begin
            acc <= acc + product;
        end
    end

    // --- Lógica de Saturação e Truncamento ---
    // O acumulador está em Q16.16. Queremos extrair o Q8.8 "central".
    // No formato Q16.16: bits [31:16] são inteiros, [15:0] são fracionários.
    // No formato Q8.8: bits [15:8] são inteiros, [7:0] são fracionários.
    // O valor correspondente no acumulador está nos bits [23:8].

    always @(*) begin
        // Verificação de Overflow Positivo:
        // O valor é maior que o máximo positivo do Q8.8 (+127.996)
        // Isso ocorre se o bit de sinal for 0 e houver bits significativos acima da faixa Q8.8
        if (acc[31] == 1'b0 && (|acc[30:23])) begin
            final_pixel = 16'h7FFF; 
        end
        // Verificação de Overflow Negativo (Saturação Negativa):
        // O valor é menor que o mínimo negativo do Q8.8 (-128.0)
        // Isso ocorre se o bit de sinal for 1 e os bits acima da faixa Q8.8 não forem todos '1' (extensão de sinal)
        else if (acc[31] == 1'b1 && !(&acc[30:23])) begin
            final_pixel = 16'h8000;
        end
        // Caso normal: extrai a parte central do acumulador
        else begin
            final_pixel = acc[23:8];
        end
    end

endmodule





`timescale 1ns / 1ps

module mac_q8_8_img_tb();

    reg clk;
    reg rst_n;
    reg clear;
    reg en;
    reg [15:0] pixel;
    reg [15:0] coeff;
    wire [15:0] final_pixel;

    // Instancia o módulo (o hardware permanece o mesmo)
    mac_q8_8_img uut (
        .clk(clk), .rst_n(rst_n), .clear(clear), 
        .en(en), .pixel(pixel), .coeff(coeff), .final_pixel(final_pixel)
    );

    always #5 clk = ~clk;

    // Task para processar uma janela 2x2 completa
    task process_window_2x2(
        input [15:0] p00, input [15:0] c00,
        input [15:0] p01, input [15:0] c01,
        input [15:0] p10, input [15:0] c10,
        input [15:0] p11, input [15:0] c11
    );
        begin
            // 1. Limpa o acumulador para a nova janela
            clear = 1; @(posedge clk); clear = 0;
            
            // 2. Aplica os 4 pixels da janela
            pixel = p00; coeff = c00; en = 1; @(posedge clk);
            pixel = p01; coeff = c01; en = 1; @(posedge clk);
            pixel = p10; coeff = c10; en = 1; @(posedge clk);
            pixel = p11; coeff = c11; en = 1; @(posedge clk);
            
            en = 0;
            #1; // Pequeno delay para estabilização da lógica combinacional de saturação
        end
    endtask

    initial begin
        clk = 0; rst_n = 0; clear = 0; en = 0;
        #20 rst_n = 1;

        // --- TESTE 1: Filtro de Média (Box Blur 2x2) ---
        // Coeficientes: 0.25 (0x0040 em Q8.8) para todos.
        // Pixels: Todos 100.0 (0x6400). Resultado esperado: 100.0 (0x6400)
        $display("Teste 1: Filtro de Media 2x2 (Expect: 100.0)");
        process_window_2x2(
            16'h6400, 16'h0040, // p00 * 0.25
            16'h6400, 16'h0040, // p01 * 0.25
            16'h6400, 16'h0040, // p10 * 0.25
            16'h6400, 16'h0040  // p11 * 0.25
        );
        if (final_pixel == 16'h6400) $display("  [PASS] Media correta.");
        else $error("  [FAIL] Media errada: %h", final_pixel);

        // --- TESTE 2: Detector de Bordas Simples ---
        // Coefs: [1, -1, 0, 0]. Pixels: [200, 50, X, X]
        // Resultado: 200 - 50 = 150.0. 
        // Como 150 > 127.99, DEVE SATURAR no positivo (0x7FFF).
        $display("Teste 2: Detector de Bordas com Saturacao Positiva (Expect: 7FFF)");
        process_window_2x2(
            16'hC800, 16'h0100, // 200.0 * 1.0
            16'h3200, 16'hFF00, // 50.0  * -1.0
            16'h0000, 16'h0000, 
            16'h0000, 16'h0000
        );
        if (final_pixel == 16'h7FFF) $display("  [PASS] Saturacao positiva ok.");
        else $error("  [FAIL] Falha na saturacao: %h", final_pixel);

        // --- TESTE 3: Resultado Negativo ---
        // Coefs: [1, -1, 0, 0]. Pixels: [50, 100, X, X]
        // Resultado: 50 - 100 = -50.0 (0xCE00).
        $display("Teste 3: Resultado Negativo (Expect: CE00)");
        process_window_2x2(
            16'h3200, 16'h0100, // 50.0  * 1.0
            16'h6400, 16'hFF00, // 100.0 * -1.0
            16'h0000, 16'h0000,
            16'h0000, 16'h0000
        );
        if (final_pixel == 16'hCE00) $display("  [PASS] Resultado negativo ok.");
        else $error("  [FAIL] Valor negativo incorreto: %h", final_pixel);

        // --- TESTE 4: Saturação Negativa ---
        // Coefs: [-1, -1, -1, 0]. Pixels: [100, 100, 50, 0]
        // Resultado: -100 - 100 - 50 = -250.0. (Abaixo de -128.0)
        $display("Teste 4: Saturacao Negativa (Expect: 8000)");
        process_window_2x2(
            16'h6400, 16'hFF00, // -100
            16'h6400, 16'hFF00, // -100
            16'h3200, 16'hFF00, // -50
            16'h0000, 16'h0000
        );
        if (final_pixel == 16'h8000) $display("  [PASS] Saturacao negativa ok.");
        else $error("  [FAIL] Falha na saturacao negativa: %h", final_pixel);

        $display("Simulacao 2x2 finalizada.");
        $stop;
    end

endmodule
