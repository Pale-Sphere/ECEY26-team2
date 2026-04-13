`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/11/2026 07:57:35 PM
// Design Name: 
// Module Name: I2S_Processor_Bridge
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


module i2s_to_rms_bridge #(
    parameter WIDTH = 24
)(
    input  wire                clk,          // 100 MHz domain
    input  wire                rst,

    // From I2S (BCK domain)
    input  wire [WIDTH-1:0]    ldata_in,
    input  wire [WIDTH-1:0]    rdata_in,
    input  wire                sample_ready_in,

    // To RMS (clk domain)
    output reg  [WIDTH-1:0]    ldata_out,
    output reg  [WIDTH-1:0]    rdata_out,
    output reg                 sample_valid_out
);

// Synchronize the sample with clk

    reg sr_meta, sr_sync;

    always @(posedge clk) begin
        sr_meta <= sample_ready_in;
        sr_sync <= sr_meta;
    end

// Edge detection
    reg sr_d;

    always @(posedge clk) begin
        sr_d <= sr_sync;
    end

    wire sample_pulse = sr_sync & ~sr_d;

// Capture data safely
    reg [WIDTH-1:0] ldata_buf;
    reg [WIDTH-1:0] rdata_buf;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            ldata_buf <= 0;
            rdata_buf <= 0;
            ldata_out <= 0;
            rdata_out <= 0;
            sample_valid_out <= 0;
        end else begin

            sample_valid_out <= 0;

            if (sample_pulse) begin
                // Capture from I2S domain
                ldata_buf <= ldata_in;
                rdata_buf <= rdata_in;

                // Output (registered)
                ldata_out <= ldata_in;
                rdata_out <= rdata_in;

                sample_valid_out <= 1;
            end
        end
    end

endmodule