module conv2d_2x2_controller #(
    parameter IMG_WIDTH = 640 // Largura da imagem: define o tamanho da memória de linha
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [15:0] pixel_in,   // Pixel que entra individualmente (streaming)
    input  wire        pixel_vld,  // '1' quando o pixel_in é válido
    
    // Conexões com o módulo MAC
    output reg  [15:0] mac_pixel,  // Pixel enviado para o multiplicador
    output reg  [15:0] mac_coeff,  // Coeficiente enviado para o multiplicador
    output reg         mac_en,     // Habilita o cálculo no MAC
    output reg         mac_clear,  // Reseta o acumulador do MAC para uma nova janela
    input  wire [15:0] final_pixel // Resultado da convolução (após 4 ciclos)
);

    // --- MEMÓRIA E PONTEIROS ---
    // Armazena a linha anterior. Essencial para convoluções 2D.
    reg [15:0] line_buffer [0:IMG_WIDTH-1]; 
    // Ponteiro que indica em qual coluna estamos trabalhando
    reg [$clog2(IMG_WIDTH)-1:0] wr_ptr; 

    // --- REGISTRADORES DA JANELA 2x2 ---
    // p00 p01  <- Linha de Cima (extraída do line_buffer)
    // p10 p11  <- Linha de Baixo (pixel atual e o anterior)
    reg [15:0] p00, p01, p10, p11; 
    
    // --- MÁQUINA DE ESTADOS (FSM) ---
    // Como o MAC processa um par por vez, precisamos de 4 estados de cálculo
    reg [2:0] state;
    localparam IDLE = 3'd0, // Aguardando novo pixel
               P00  = 3'd1, // Envia pixel superior esquerdo
               P01  = 3'd2, // Envia pixel superior direito
               P10  = 3'd3, // Envia pixel inferior esquerdo
               P11  = 3'd4, // Envia pixel inferior direito (atual)
               DONE = 3'd5; // Finaliza o ciclo da janela atual

    // --- COEFICIENTES DO KERNEL (Q8.8) ---
    // Aqui definimos o comportamento do filtro (Ex: 0.25 em cada = Blur/Média)
    wire [15:0] K [0:3];
    assign K[0] = 16'h0040; // Coeficiente para p00
    assign K[1] = 16'h0040; // Coeficiente para p01
    assign K[2] = 16'h0040; // Coeficiente para p10
    assign K[3] = 16'h0040; // Coeficiente para p11

    // --- LÓGICA DE CONTROLE ---
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= 0;
            state <= IDLE;
            mac_en <= 0;
            mac_clear <= 0;
        end else begin
            // SE chegar um novo pixel: atualiza a janela e o buffer
            if (pixel_vld) begin
                // Deslocamento Horizontal e Vertical
                p11 <= pixel_in;             // Pixel atual entra no canto inferior direito
                p10 <= p11;                  // O que era atual vira "pixel da esquerda"
                p01 <= line_buffer[wr_ptr];  // Puxa da memória o pixel que passou por aqui na linha anterior
                p00 <= p01;                  // Desloca o pixel da linha de cima para a esquerda
                
                // Atualiza a memória de linha com o pixel atual para ser usado na PRÓXIMA linha
                line_buffer[wr_ptr] <= pixel_in;
                
                // Controle do ponteiro da coluna
                wr_ptr <= (wr_ptr == IMG_WIDTH-1) ? 0 : wr_ptr + 1;
                
                // Dispara o processamento sequencial no MAC
                state <= P00;
            end 
            // SE não chegou pixel novo, mas a FSM está rodando:
            else begin
                case (state)
                    P00: begin 
                        mac_clear <= 1;       // Primeiro ciclo: limpa o acumulador do MAC
                        mac_en    <= 1;       // Habilita o cálculo
                        mac_pixel <= p00;     // Entrega o dado
                        mac_coeff <= K[0];    // Entrega o peso
                        state     <= P01; 
                    end
                    P01: begin 
                        mac_clear <= 0;       // Para de limpar para permitir o acúmulo
                        mac_pixel <= p01; 
                        mac_coeff <= K[1]; 
                        state     <= P10; 
                    end
                    P10: begin 
                        mac_pixel <= p10; 
                        mac_coeff <= K[2]; 
                        state     <= P11; 
                    end
                    P11: begin 
                        mac_pixel <= p11; 
                        mac_coeff <= K[3]; 
                        state     <= DONE; 
                    end
                    DONE: begin 
                        mac_en <= 0;          // Desliga o MAC (resultado está pronto em 'final_pixel')
                        state  <= IDLE; 
                    end
                    default: state <= IDLE;
                endcase
            end
        end
    end
endmodule



`timescale 1ns / 1ps

module conv2d_2x2_controller_robust_tb();

    // --- CONFIGURAÇÕES ---
    parameter WIDTH = 4;         // Largura de apenas 4 pixels para debug fácil
    parameter CLK_PERIOD = 10;
    
    // --- SINAIS ---
    reg         clk, rst_n;
    reg  [15:0] pixel_in;
    reg         pixel_vld;
    wire [15:0] mac_pixel, mac_coeff;
    wire        mac_en, mac_clear;
    reg  [15:0] final_pixel_mock; // Apenas para fechar a porta do DUT

    // Instância do Controlador
    conv2d_2x2_controller #(.IMG_WIDTH(WIDTH)) dut (
        .clk(clk), .rst_n(rst_n),
        .pixel_in(pixel_in), .pixel_vld(pixel_vld),
        .mac_pixel(mac_pixel), .mac_coeff(mac_coeff),
        .mac_en(mac_en), .mac_clear(mac_clear),
        .final_pixel(final_pixel_mock)
    );

    // Clock de 100MHz
    always #(CLK_PERIOD/2) clk = ~clk;

    // --- TASK: Enviar Pixel ---
    // Facilita o envio de dados e sincroniza com a FSM do controlador
    task send_pixel(input [15:0] val);
        begin
            @(posedge clk);
            pixel_in = val;
            pixel_vld = 1;      // Sinaliza dado válido por 1 ciclo
            @(posedge clk);
            pixel_vld = 0;
            repeat(6) @(posedge clk); // Espera a FSM do controlador (5 estados + folga)
        end
    endtask

    // --- TASK: Enviar Linha ---
    // Envia 'WIDTH' pixels. O segredo está no valor: 0xRRCC (R=Row, C=Column)
    task send_row(input [7:0] row_index);
        integer i;
        begin
            $display("[%0t] Enviando Linha %0d...", $time, row_index);
            for (i = 0; i < WIDTH; i = i + 1) begin
                // Ex: Linha 2, Coluna 3 vira o valor Hex 0x0203
                send_pixel({row_index, i[7:0]}); 
            end
        end
    endtask

    // --- PROCEDIMENTO DE TESTE ---
    initial begin
        // Início
        clk = 0; rst_n = 0; pixel_vld = 0; pixel_in = 0;
        #(CLK_PERIOD * 2) rst_n = 1;

        // PASSO 1: Encher o Line Buffer (Primeira Linha)
        // Como não há linha acima desta, os pixels p00 e p01 serão lixo ou zero.
        send_row(8'h01); 

        // PASSO 2: Validar a Janela (Segunda Linha)
        // Ao enviar a linha 2, o controlador deve puxar a linha 1 da memória.
        // Se no Waveform você vir p11=0x0201 e p01=0x0101, a sincronia está perfeita!
        send_row(8'h02);

        // PASSO 3: Deslizamento Vertical
        // Agora o buffer deve soltar a linha 2 e salvar a linha 3.
        send_row(8'h03);

        $display("[%0t] Teste finalizado. Verifique o Waveform para validar os cruzamentos 0xRRCC.", $time);
        $stop;
    end

endmodule


//Casos de Teste Cobertos:
//Fase de Warm-up: O momento em que o Line Buffer ainda está vazio (primeira linha).

//Vertical Sliding: A transição da Linha 2 para a Linha 3, garantindo que o buffer está "esquecendo" a linha antiga.

//Horizontal Wrap: Quando o wr_ptr atinge IMG_WIDTH-1 e volta para 0.

//Latência da FSM: Garante que o mac_clear só pulsa no início de cada janela e os 4 coeficientes (K[0] a K[3]) são aplicados na ordem correta.

//Dica para o Debug:
//Ao rodar essa TB, adicione os sinais dut.p00, dut.p01, dut.p10, dut.p11 ao seu Waveform. 
//Durante o Caso 2, você deverá ver os valores de 0x01xx (linha anterior) e 0x02xx (linha atual) cruzando-se exatamente nos estados do MAC.