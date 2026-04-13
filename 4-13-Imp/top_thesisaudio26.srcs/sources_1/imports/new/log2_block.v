`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// log2_block.v
//
// Computes fixed-point log2 of an unsigned 24-bit input.
//
// Output format: 5.10 fixed-point (15 bits total)
//   [14:10] = integer part (0..23, position of MSB)
//   [9:0]   = fractional part (linear interpolation from mantissa bits)
//
// Method:
//   1. Priority encoder finds highest set bit position → integer part
//   2. Input is left-shifted to normalize: the bits below the MSB form
//      a mantissa in [0,1). The top 10 bits of this = fractional part.
//   3. This is equivalent to linear interpolation between powers of 2,
//      which approximates log2 with < 0.1% error for large values.
//   4. Special case: input=0 → output=0, zero_flag asserted
//
// Latency: 1 clock cycle
// Resources: ~50 LUTs, 16 FFs
//////////////////////////////////////////////////////////////////////////////////

module log2_block #(
    parameter INPUT_WIDTH = 24,
    parameter FRAC_BITS   = 10
)(
    input  wire                        clk,
    input  wire                        rst,
    input  wire [INPUT_WIDTH-1:0]      din,
    input  wire                        din_valid,
    output reg  [4+FRAC_BITS:0]        log2_out,   // 5.10 = 15 bits
    output reg                         log2_valid,
    output reg                         zero_flag    // HIGH when input was 0
);

    localparam INT_BITS  = 5;
    localparam OUT_WIDTH = INT_BITS + FRAC_BITS;

    // Priority encoder: find position of highest set bit
    function [INT_BITS-1:0] find_msb;
        input [INPUT_WIDTH-1:0] val;
        integer i;
        begin
            find_msb = 0;
            for (i = 0; i < INPUT_WIDTH; i = i + 1) begin
                if (val[i])
                    find_msb = i[INT_BITS-1:0];
            end
        end
    endfunction

    // Barrel shift: normalize input so MSB is at position INPUT_WIDTH-1
    // Then take top FRAC_BITS below that as the fractional part
    //
    // Example for INPUT_WIDTH=24, FRAC_BITS=10:
    //   If MSB is at position 20, we shift left by 3 (=23-20)
    //   Bits [22:13] become the fractional part (bit 23 is the implicit 1)
    function [FRAC_BITS-1:0] get_fraction;
        input [INPUT_WIDTH-1:0] val;
        input [INT_BITS-1:0]    msb_pos;
        reg [INPUT_WIDTH-1:0]   shifted;
        begin
            // Shift so the MSB lands at bit INPUT_WIDTH-1
            shifted = val << (INPUT_WIDTH - 1 - msb_pos);
            // Take the bits just below the MSB as fraction
            // Bit INPUT_WIDTH-1 is the implicit '1', bits below it are the mantissa
            get_fraction = shifted[INPUT_WIDTH-2 -: FRAC_BITS];
        end
    endfunction

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            log2_out   <= 0;
            log2_valid <= 1'b0;
            zero_flag  <= 1'b0;
        end else begin
            log2_valid <= din_valid;

            if (din_valid) begin
                if (din == 0) begin
                    log2_out  <= 0;
                    zero_flag <= 1'b1;
                end else begin
                    zero_flag <= 1'b0;
                    log2_out  <= {find_msb(din), get_fraction(din, find_msb(din))};
                end
            end
        end
    end

endmodule
