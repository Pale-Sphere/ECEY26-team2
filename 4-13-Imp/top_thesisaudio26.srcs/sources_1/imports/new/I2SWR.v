`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:  Kemal Okvuran
// Engineer: 
// 
// Create Date: 03/26/2026 08:14:35 AM
// Design Name: 
// Module Name: I2Sreciever_sample_ready
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// I2S reciever with sample ready and designed to handle a 24 bit sample with an initial dead bit
// Dependencies: 
// 
// Revision:
// 
// Additional Comments:
//  Mostly based on the code here https://www.beyond-circuits.com/wordpress/tutorial/tutorial18/part2/discussion/
//////////////////////////////////////////////////////////////////////////////////


module I2Sreciever_sample_ready #(parameter width = 24)
  (
   input                  bck,
   input                  din,
   input                  lrck,
   input                  rst,
   output reg [width-1:0] ldata,
   output reg [width-1:0] rdata,
   output reg             sample_ready
   );

  // Two-flop edge detector
  reg wsd, wsdd;
  always @(posedge bck)
    if (rst) wsd <= 0;
    else     wsd <= lrck;

  always @(posedge bck)
    if (rst) wsdd <= 0;
    else     wsdd <= wsd;

  wire wsp = wsd ^ wsdd;

  // Bit counter on negedge BCK
  localparam CNT_BITS = $clog2(width+2);
  reg [CNT_BITS-1:0] counter;

  always @(negedge bck)
    if (rst)                   counter <= 0;
    else if (wsp)              counter <= 0;
    else if (counter <= width) counter <= counter + 1;

  // Enable decode
  wire [width:0] en;
  genvar g;
  generate
    for (g = 0; g <= width; g = g + 1) begin : gen_en
      assign en[g] = (counter == g);
    end
  endgenerate

  // Individual flip-flops, MSB-first
  // counter==1 -> shift[width-1] (MSB)
  // counter==width -> shift[0]   (LSB)
  // No wsp reset - latch reads shift on same posedge as wsp,
  // so clearing here would overwrite good data with zeros before latch sees it.
  // New frame bits naturally overwrite from MSB after the dead cycle anyway.
  reg [width-1:0] shift;
  generate
    for (g = 1; g <= width; g = g + 1) begin : gen_ff
      always @(posedge bck)
        if (rst)        shift[width-g] <= 1'b0;
        else if (en[g]) shift[width-g] <= din;
    end
  endgenerate

  // Output latches
  // LRCK rising  (wsd=1, wsdd=0, wsp=1) → left  channel done
  // LRCK falling (wsd=0, wsdd=1, wsp=1) → right channel done
  always @(posedge bck)
    begin
      sample_ready <= 1'b0;
      if (wsp && wsd) begin
        ldata <= shift;
      end
      if (wsp && !wsd) begin
        rdata        <= shift;
        sample_ready <= 1'b1;
      end
    end

endmodule
