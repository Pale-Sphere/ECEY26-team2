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
`timescale 1ns / 1ps

module spi_tx #(    
    parameter BIT_WIDTH = 24, //Parameter to configure the bit-width of theta as needed
    parameter HEADER = 8'hAA, //Parameter to configure a header of spi-data
    parameter HEADER_WIDTH = 8
)( 
    input wire clk,
    input wire rst,
    
    input wire ce, //active low chip enable signal
    input wire sclk, //system clock from the master (raspberry pi)
    input wire [(BIT_WIDTH - 1):0] theta, 
    input wire theta_valid,
    output reg sdo //serial data out
    );

localparam TOTAL_WIDTH = BIT_WIDTH + HEADER_WIDTH;

//register declarations
reg [(TOTAL_WIDTH - 1):0] shift_reg; 
reg [(TOTAL_WIDTH - 1):0] frame_reg; //a latched frame register to add the header to theta and guarantee it isn't changed during transmission
reg [5:0] bit_counter;

//2 flip-flop synchonizer for system clock and the enable
reg sclk_meta, sclk_synch;
reg ce_meta, ce_synch;
always @(posedge clk) begin
    sclk_meta <= sclk;
    sclk_synch <= sclk_meta;
    ce_meta <= ce;
    ce_synch <= ce_meta;
end

reg sclk_d;
reg ce_d;

always @(posedge clk) begin
    sclk_d <= sclk_synch;
    //ce_d <= ce_synch; no longer needed with handshake protocol
end


//edge detection logic
wire sclk_r = (sclk_d == 0 && sclk_synch == 1); //rising edge of raspberry pi's clock
//wire ce_f = (ce_d == 1 && ce_synch == 0); no longer needed with handshake protocol

//Latching theta and creating a frame with the HEADER
always @ (posedge clk) begin
    if (theta_valid && ce_synch) begin
        frame_reg <= {HEADER, theta}; //store theta into the latched register while a transmission isn't happening and add the header
    end
end

//SPI Communication
always @(posedge clk or posedge rst) begin
    if (rst) begin //reset the intermediate registers
        shift_reg <= 0;
        bit_counter <= 0;
        sdo <= 0;
    end else begin
        
        if (ce_synch) begin //if ce is high, the system is idling
            bit_counter <= 0;
        end else begin
            
            if (bit_counter == 0) begin
                shift_reg <= frame_reg;
            end
            if (sclk_r) begin
                sdo <= shift_reg[(TOTAL_WIDTH - 1)];
                shift_reg <= {shift_reg[(TOTAL_WIDTH - 2):0], (1'b0)};
                bit_counter <= bit_counter + 1;
            end
        end
    end
end

endmodule
