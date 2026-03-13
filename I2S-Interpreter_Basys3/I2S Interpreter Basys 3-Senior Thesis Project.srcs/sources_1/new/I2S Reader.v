`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Yale University
// Engineer: Evan Losey
// 
// Create Date: 03/12/2026 02:08:53 PM
// Design Name: 
// Module Name: I2S Receiver
// Project Name: 
// Target Devices: Basys 3 Board
// Tool Versions: Vivado 2017.4
// Description: A reciever module made to interpret the incoming I2S data from a stereo PCM1808EVM evaluation board 
// taking the input from two non-stereo microphones. The Basys 3 will run in master mode driving the system clock, while the
// evaluation board will handle and output the sub-clocks (word select, data clock, etc.)
// 
// I/O pins are mainly derived from the outputs of the evaluation board, so it may differ from other naming conventions
//
// Data-Length = 24 bits
//
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments: code was built with the help of this tutorial: https://www.beyond-circuits.com/wordpress/tutorial/tutorial18/
// 
//////////////////////////////////////////////////////////////////////////////////


module I2Sreceiver(
    //output scko, //system/master clock
    input lrck, //word select clock (derived by evaluation board)
    input bck,  //bit/data clock for the serial (can be sck in other versions)
    input din,  //inputted data
    input rst,  //reset wire
    output reg[23:0]ldata, //data for the left (white) microphone
    output reg[23:0]rdata  //data for the right (red) microphone
    );
    
    
    reg lrd;   //Two flip flops to delay the clock cycle by one (lrd) & capture the last(lrdd) ws to see change
    reg lrdd;  //left data output register (lrp)
    wire lrp = lrd ^ lrdd;  //detects the edge of the lrck
    wire lenable = lrd & lrp; //Enable wires for the output registers
    wire renable = !lrd & lrp;
    
    //find the ws of n-1 and n-2 for falling edge detection with cascading flip flops
    always @(posedge bck) begin
       if (rst) begin
            lrd <= 1'b0;
            lrdd <= 1'b0;
       end
       else begin 
            lrd <= lrck;
            lrdd <= lrd;
       end
    end
       
    //Main 24b Shift Register
    reg[23:0] shift;
    always @(posedge bck) begin
        if (rst) begin
            shift <= 24'b0;
            ldata <= 24'b0;
            rdata <= 24'b0;
        end
        else begin
            shift <= {shift[22:0], din};
        end
        
    //Branching enables for output registers
        if (lenable) begin
            ldata <= shift;
        end
        if (renable) begin
            rdata <= shift;
        end
    end

endmodule
