

module mac_q8_8_conv (
    input  wire        clk,
    input  wire        rst_n,      // Reset assíncrono (ativo baixo)
    input  wire        clear,      // Zera o acumulador para um novo pixel
    input  wire        en,         // Habilita a computação (enable)
    input  wire [15:0] pixel,      // Entrada Q8.8
    input  wire [15:0] coeff,      // Coeficiente do Kernel Q8.8
    output reg  [15:0] final_pixel // Saída saturada Q8.8
);

    // Acumulador de 32 bits (Formato interno Q16.16)
    reg signed [31:0] acc;

    // Fio para o produto da multiplicação atual
    wire signed [31:0] product;

    // Multiplicação com sinal
    assign product = $signed(pixel) * $signed(coeff);

    // Lógica do Acumulador
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc <= 32'd0;
        end else if (clear) begin
            acc <= 32'd0;
        end else if (en) begin
            acc <= acc + product;
        end
    end

    // Lógica Combinacional de Saturação
    // Esta parte "decide" o valor de saída com base no estado atual do ACC
    always @(*) begin
        // Verificação de Overflow Positivo:
        // Se o bit de sinal [31] é 0, mas há bits '1' entre [30:23]
        if (acc[31] == 1'b0 && |acc[30:23]) begin
            final_pixel = 16'h7FFF; // Valor máximo positivo (+127.996)
        end
        // Verificação de Overflow Negativo:
        // Se o bit de sinal [31] é 1, mas há bits '0' entre [30:23]
        else if (acc[31] == 1'b1 && !(&acc[30:23])) begin
            final_pixel = 16'h8000; // Valor máximo negativo (-128.0)
        end
        // Caso contrário, o valor está dentro da faixa permitida
        else begin
            final_pixel = acc[23:8];
        end
    end

endmodule




`timescale 1ns / 1ps

module mac_q8_8_tb();

    // Sinais do Sistema
    reg clk;
    reg rst_n;
    reg clear;
    reg en;
    reg  [15:0] pixel;
    reg  [15:0] coeff;
    wire [15:0] final_pixel;

    // Instância do Unit Under Test (UUT)
    mac_q8_8_conv uut (
        .clk(clk),
        .rst_n(rst_n),
        .clear(clear),
        .en(en),
        .pixel(pixel),
        .coeff(coeff),
        .final_pixel(final_pixel)
    );

    // Definições de Ponto Fixo Q8.8
    localparam FIXED_ONE = 16'h0100; // 1.0 em Q8.8
    localparam MAX_POS   = 16'h7FFF; // +127.996
    localparam MAX_NEG   = 16'h8000; // -128.0

    // Geração de Clock (100MHz)
    always #5 clk = ~clk;

    // Task para simplificar a aplicação de estímulos
    task mac_op(input [15:0] p, input [15:0] c);
        begin
            pixel = p;
            coeff = c;
            en = 1;
            @(posedge clk);
            en = 0;
        end
    endtask

    initial begin
        // --- Inicialização ---
        clk = 0;
        rst_n = 0;
        clear = 0;
        en = 0;
        pixel = 0;
        coeff = 0;

        $display("Iniciando Testbench Robusta Q8.8...");
        #20 rst_n = 1; // Solta o reset
        #10;

        // --- TESTE 1: Reset e Clear ---
        $display("Teste 1: Verificando Reset/Clear");
        mac_op(16'h0500, 16'h0200); // 5.0 * 2.0 = 10.0
        #5;
        clear = 1;
        @(posedge clk);
        clear = 0;
        if (uut.acc == 0) $display("  [PASS] Acumulador zerado com sucesso.");
        else $error("  [FAIL] Falha ao zerar acumulador.");

        // --- TESTE 2: Operação Simples e Acumulação ---
        // Vamos calcular (2.5 * 2.0) + (1.0 * 3.0) = 5.0 + 3.0 = 8.0
        $display("Teste 2: Acumulação Simples");
        mac_op(16'h0280, 16'h0200); // 2.5 * 2.0
        mac_op(16'h0100, 16'h0300); // 1.0 * 3.0
        #1; // Espera estabilizar combinacional
        if (final_pixel == 16'h0800) $display("  [PASS] 2.5*2 + 1*3 = 8.0 (0x0800)");
        else $error("  [FAIL] Resultado incorreto: %h", final_pixel);

        // --- TESTE 3: Saturação Positiva ---
        // Vamos forçar um estouro: 64.0 * 3.0 = 192.0 (Limite é 127.99)
        $display("Teste 3: Saturação Positiva");
        clear = 1; @(posedge clk); clear = 0;
        mac_op(16'h4000, 16'h0300); // 64 * 3
        #1;
        if (final_pixel == MAX_POS) $display("  [PASS] Saturou corretamente em MAX_POS");
        else $error("  [FAIL] Nao saturou positivo. Valor: %h", final_pixel);

        // --- TESTE 4: Saturação Negativa ---
        // -64.0 * 3.0 = -192.0 (Limite é -128.0)
        $display("Teste 4: Saturação Negativa");
        clear = 1; @(posedge clk); clear = 0;
        mac_op(16'hC000, 16'h0300); // -64 * 3 (C000 em 2's comp = -64)
        #1;
        if (final_pixel == MAX_NEG) $display("  [PASS] Saturou corretamente em MAX_NEG");
        else $error("  [FAIL] Nao saturou negativo. Valor: %h", final_pixel);

        // --- TESTE 5: Multiplicação com Fração ---
        // 0.5 * 0.5 = 0.25 (0x0080 * 0x0080 = 0x0040)
        $display("Teste 5: Precisão Fracionária");
        clear = 1; @(posedge clk); clear = 0;
        mac_op(16'h0080, 16'h0080); 
        #1;
        if (final_pixel == 16'h0040) $display("  [PASS] 0.5 * 0.5 = 0.25 (0x0040)");
        else $error("  [FAIL] Erro na precisão: %h", final_pixel);

        $display("Testbench Finalizada.");
        $finish;
    end

endmodule