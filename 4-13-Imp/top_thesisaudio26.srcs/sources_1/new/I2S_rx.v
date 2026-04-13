`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/13/2026 12:51:24 PM
// Design Name: 
// Module Name: I2S_rx
// Project Name: 
// Target Devices: 
// Tool Versions: 
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

module I2S_rx #(
    parameter WIDTH = 24
)(
    input                  clk,      // 100 MHz system clock
    input                  rst,

    input                  bck,      // external I2S signals
    input                  din,
    input                  lrck,

    output reg [WIDTH-1:0] ldata,
    output reg [WIDTH-1:0] rdata,
    output reg             sample_ready
);

  // ============================================================
  // 1. Synchronize inputs to clk domain
  // ============================================================
  reg [2:0] bck_sync, lrck_sync, din_sync;

  always @(posedge clk) begin
    bck_sync  <= {bck_sync[1:0], bck};
    lrck_sync <= {lrck_sync[1:0], lrck};
    din_sync  <= {din_sync[1:0], din};
  end

  wire bck_rising  = (bck_sync[2:1] == 2'b01);
  wire bck_falling = (bck_sync[2:1] == 2'b10);
  wire wsp         = (lrck_sync[2] ^ lrck_sync[1]);  // edge detect
  wire ws          = lrck_sync[2];

  // ============================================================
  // 2. Counter (runs on clk, enabled by bck_falling)
  // ============================================================
  localparam CNT_BITS = $clog2(WIDTH+2);
  reg [CNT_BITS-1:0] counter;

  always @(posedge clk) begin
    if (rst)
      counter <= 0;
    else if (wsp)
      counter <= 0;
    else if (bck_falling && counter <= WIDTH)
      counter <= counter + 1;
  end

  // ============================================================
  // 3. Shift register (enabled by bck_rising)
  // ============================================================
  reg [WIDTH-1:0] shift;

  integer i;
  always @(posedge clk) begin
    if (rst) begin
      shift <= 0;
    end else if (bck_rising) begin
      if (counter >= 1 && counter <= WIDTH) begin
        // MSB first
        shift <= {shift[WIDTH-2:0], din_sync[2]};
      end
    end
  end

  // ============================================================
  // 4. Output latch (same logic as before)
  // ============================================================
  always @(posedge clk) begin
    sample_ready <= 1'b0;

    if (wsp && ws) begin
      ldata <= shift;
    end

    if (wsp && !ws) begin
      rdata        <= shift;
      sample_ready <= 1'b1;
    end
  end

endmodule
