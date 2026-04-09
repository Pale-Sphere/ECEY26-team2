`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Yale University
// Engineer: Evan Losey
// 
// Create Date: 03/26/2026 09:55:29 PM
// Design Name: spi-tx
// Module Name: spi_tx
// Project Name: FRANCINE
// Target Devices: Basys 3 Prototyping Board (slave) to Raspberry Pi (master)
// Tool Versions: Vivado 2020.2
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module top_spi(

    input wire clk,     // 100 MHz onboard
    input wire rst,

    // SPI from Raspberry Pi
    input wire sclk,
    input wire ce,
    output wire sdo

);

// Instantiated inputs
wire [23:0] theta;
wire theta_valid;

// Constant Test Value
assign theta = 24'hA5B6C7;
assign theta_valid = 1'b1;

// Instantiated SPI module
spi_tx spi_inst (
    .clk(clk),
    .rst(rst),
    .sclk(sclk),
    .ce(ce),
    .sdo(sdo),
    .theta(theta),
    .theta_valid(theta_valid)
);

endmodule
