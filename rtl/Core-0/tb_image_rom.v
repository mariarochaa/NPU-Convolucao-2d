`timescale 1ns/1ps

module tb_image_rom;
    reg        clk;
    reg  [9:0] addr;
    wire [7:0] data_out;

    image_rom dut (
        .clk(clk),
        .addr(addr),
        .data_out(data_out)
    );

    initial clk = 0;
    always #5 clk = ~clk;  // clock 100 MHz

    initial begin
        addr = 0;

        // Lê primeiros 16 pixels
        repeat (16) begin
            @(posedge clk);
            $display("addr=%0d data=%0h", addr, data_out);
            addr <= addr + 1;
        end

       
    end
endmodule