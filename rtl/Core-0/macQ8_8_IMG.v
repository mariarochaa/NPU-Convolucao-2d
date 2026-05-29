

`timescale 1ns / 1ps

module mac_q8_8_img_tb();

    reg clk;
    reg rst_n;
    reg clear;
    reg en;
    reg [15:0] pixel;
    reg [15:0] coeff;
    wire [15:0] final_pixel;

    mac_q8_8_img uut (
        .clk(clk), .rst_n(rst_n), .clear(clear), 
        .en(en), .pixel(pixel), .coeff(coeff), .final_pixel(final_pixel)
    );

    always #5 clk = ~clk;

    task apply_val(input [15:0] p, input [15:0] c);
        begin
            pixel = p; coeff = c; en = 1;
            @(posedge clk); en = 0;
        end
    endtask

    initial begin
        clk = 0; rst_n = 0; clear = 0; en = 0;
        #20 rst_n = 1;

        // --- TESTE 1: Pixel Alto (MSB=1) interpretado como Unsigned ---
        // Se o pixel 0x8000 (128.0) for interpretado como signed, seria -128.
        // Como é imagem (unsigned), 128.0 * 1.0 deve dar 128.0 (e saturar para 127.99)
        $display("Teste 1: Validando Pixel MSB (128.0 * 1.0)");
        clear = 1; @(posedge clk); clear = 0;
        apply_val(16'h8000, 16'h0100); // 128.0 * 1.0
        #1;
        if (final_pixel == 16'h7FFF) 
            $display("  [PASS] 128.0 interpretado como positivo (Saturou em 127.99)");
        else 
            $error("  [FAIL] Erro de interpretacao: %h", final_pixel);

        // --- TESTE 2: Operacao de Kernels (Diferenca/Bordas) ---
        // (Pixel 200.0 * Coeff -1.0) = -200.0 (Deve saturar no minimo -128.0)
        $display("Teste 2: Pixel Positivo * Coeficiente Negativo");
        clear = 1; @(posedge clk); clear = 0;
        apply_val(16'hC800, 16'hFF00); // 200.0 * -1.0
        #1;
        if (final_pixel == 16'h8000)
            $display("  [PASS] Resultado negativo saturado corretamente em -128.0");
        else
            $error("  [FAIL] Falha na saturacao negativa: %h", final_pixel);

        // --- TESTE 3: Acumulo de Convolucao 3x3 (Sobel Vertical) ---
        // Simulando pixels de uma borda: [255, 255, 255] com pesos [1, 2, 1]
        // Total esperado: (255*1 + 255*2 + 255*1) = 1020.0 -> Deve saturar no MAX
        $display("Teste 3: Acumulo de Kernel de Brilho (Saturacao Positiva)");
        clear = 1; @(posedge clk); clear = 0;
        apply_val(16'hFF00, 16'h0100); // 255 * 1
        apply_val(16'hFF00, 16'h0200); // 255 * 2
        apply_val(16'hFF00, 16'h0100); // 255 * 1
        #1;
        if (final_pixel == 16'h7FFF)
            $display("  [PASS] Acumulo de brilho saturado em 127.99");
        else
            $error("  [FAIL] Erro no acumulo: %h", final_pixel);

        // --- TESTE 4: Multiplicacao por Zero e Identidade ---
        $display("Teste 4: Identidade e Zero");
        clear = 1; @(posedge clk); clear = 0;
        apply_val(16'h5000, 16'h0000); // 80.0 * 0
        apply_val(16'h1234, 16'h0100); // 0 + (18.2 * 1.0)
        #1;
        if (final_pixel == 16'h1234)
            $display("  [PASS] Identidade ok: %h", final_pixel);
        else
            $error("  [FAIL] Erro na identidade: %h", final_pixel);

        $display("Simulacao concluida com sucesso.");
        $finish;
    end
endmodule


`timescale 1ns / 1ps

module mac_q8_8_img_2x2_tb();

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
        $finish;
    end

endmodule


//O que mudou e por que é importante?Task process_window_2x2: Em hardware real, 
//o controlador de memória vai enviar os dados em rajadas (bursts). A testbench agora mimetiza isso: 
//pulsa o clear e depois envia exatamente 4 pares de dados.Teste de Média (Box Blur): 
//É o teste mais comum em convolução. Usei o coeficiente 0x0040 ($0.25$ em Q8.8). 
//Como temos 4 pixels na janela, a soma de $4 \times 0.25 = 1.0$. Se os pixels forem idênticos, a saída deve ser igual à entrada.
// É uma forma perfeita de validar se a vírgula do ponto fixo não saiu do lugar.Fluxo de Saturação: 
//Observe o Teste 2. Um pixel de brilho $200.0$ é comum em imagens, mas nosso formato Q8.8 só vai até $127.99$ na parte inteira com sinal. 
//Isso confirma que a saturação é vital quando você lida com ganhos ou filtros que realçam o contraste.