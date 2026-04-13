`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// rms_block.v
//
// Computes RMS over a 256-sample non-overlapping window of 24-bit audio.
//
// Algorithm:
//   1. Accumulate sum of squares over 256 samples  (ACCUMULATE state)
//   2. Divide by 256 (arithmetic right shift by 8)  (instant)
//   3. Compute integer square root via binary search (SQRT state)
//   4. Assert rms_valid for one cycle with result    (DONE state)
//   5. Return to ACCUMULATE for next window
//
// Bit widths:
//   Input sample : 24-bit signed (sign-extended from I2S receiver)
//   Square       : 48-bit unsigned (24 × 24)
//   Accumulator  : 57-bit unsigned (48-bit square × 256 samples needs
//                  log2(256) = 8 extra bits → 56 bits; +1 for safety = 57)
//   Mean of sq.  : 49-bit (57 - 8)
//   RMS result   : 25-bit (ceil(49/2))  →  output truncated to 24 bits
//
// Square root:
//   Uses a restoring binary search (non-restoring digit-by-step method).
//   Takes 25 clock cycles in SQRT state — well within the ~21ms between
//   windows at 48 kHz. No DSP slices used for sqrt; only the squaring
//   step uses a DSP.
//
// Latency:
//   256 samples to fill window + 25 cycles for sqrt + 1 cycle DONE
//   = 282 cycles of clk_100mhz per result. At 48 kHz and 100 MHz system
//   clock this is ~5.3 µs compute time for a ~5.3 ms window — fine.
//
// Ports:
//   clk         - 100 MHz system clock
//   rst         - synchronous active-high reset
//   sample_in   - 24-bit signed audio sample from FIFO dout
//   sample_valid- connect to FIFO 'valid' strobe; HIGH when sample_in is good
//   rms_out     - 24-bit RMS result
//   rms_valid   - HIGH for one cycle when rms_out holds a new valid result
//////////////////////////////////////////////////////////////////////////////////

`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// rms_block.v
//
// Computes RMS over a 256-sample non-overlapping window of 24-bit audio.
//
// Algorithm:
//   1. Accumulate sum of squares over 256 samples  (ACCUMULATE state)
//   2. Divide by 256 (arithmetic right shift by 8)  (instant)
//   3. Compute integer square root via binary search (SQRT state)
//   4. Assert rms_valid for one cycle with result    (DONE state)
//   5. Return to ACCUMULATE for next window
//
// Bit widths:
//   Input sample : 24-bit signed (sign-extended from I2S receiver)
//   Square       : 48-bit unsigned (24 � 24)
//   Accumulator  : 57-bit unsigned (48-bit square � 256 samples needs
//                  log2(256) = 8 extra bits ? 56 bits; +1 for safety = 57)
//   Mean of sq.  : 49-bit (57 - 8)
//   RMS result   : 25-bit (ceil(49/2))  ?  output truncated to 24 bits
//
// Square root:
//   Uses a restoring binary search (non-restoring digit-by-step method).
//   Takes 25 clock cycles in SQRT state - well within the ~21ms between
//   windows at 48 kHz. No DSP slices used for sqrt; only the squaring
//   step uses a DSP.
//
// Latency:
//   256 samples to fill window + 25 cycles for sqrt + 1 cycle DONE
//   = 282 cycles of clk_100mhz per result. At 48 kHz and 100 MHz system
//   clock this is ~5.3 �s compute time for a ~5.3 ms window - fine.
//
// Ports:
//   clk         - 100 MHz system clock
//   rst         - synchronous active-high reset
//   sample_in   - 24-bit signed audio sample from FIFO dout
//   sample_valid- connect to FIFO 'valid' strobe; HIGH when sample_in is good
//   rms_out     - 24-bit RMS result
//   rms_valid   - HIGH for one cycle when rms_out holds a new valid result
//////////////////////////////////////////////////////////////////////////////////

`timescale 1ns / 1ps

module rms_block (
    input  wire        clk,
    input  wire        rst,

    input  wire signed [23:0] sample_in,
    input  wire               sample_valid,

    output reg  [23:0] rms_out,
    output reg         rms_valid
);

    // ?? State machine ?????????????????????????????????????????????????????????
    localparam S_ACCUMULATE = 2'd0;
    localparam S_SQRT       = 2'd1;
    localparam S_DONE       = 2'd2;

    reg [1:0] state;

    // ?? Sample counter (0..255) ???????????????????????????????????????????????
    reg [7:0] sample_count;

    // ?? Squaring (PIPELINED) ??????????????????????????????????????????????????
    reg  [23:0] sample_abs_d;
    reg  [47:0] square;

    always @(posedge clk) begin
        if (rst) begin
        sample_abs_d <= 24'd0;
        square       <= 48'd0;
        sample_abs_d <= 24'd0;
        end else begin
            sample_abs_d <= sample_in[23] ? (~sample_in + 1'b1) : sample_in;
            square       <= sample_abs_d * sample_abs_d;
        end
    end

    // Align valid with pipeline
    reg sample_valid_d;
    always @(posedge clk) begin
        sample_valid_d <= sample_valid;
    end

    // ?? Accumulator ???????????????????????????????????????????????????????????
    reg [56:0] accumulator;

    // ?? Mean of squares ???????????????????????????????????????????????????????
    reg [48:0] mean_sq;

    // ?? Binary search square root ?????????????????????????????????????????????
    reg [24:0] sqrt_result;
    reg [24:0] sqrt_bit;

    // PIPELINED SQRT additions
    reg [24:0] candidate;
    reg [49:0] candidate_sq;
    reg        sqrt_phase;

    // ?? State machine ?????????????????????????????????????????????????????????
    always @(posedge clk) begin
        if (rst) begin
            state        <= S_ACCUMULATE;
            sample_count <= 8'd0;
            accumulator  <= 57'd0;
            mean_sq      <= 49'd0;
            sqrt_result  <= 25'd0;
            sqrt_bit     <= 25'd0;
            rms_out      <= 24'd0;
            rms_valid    <= 1'b0;

            // New regs
            //sample_abs_d <= 24'd0;
            //square       <= 48'd0; removed due to weird bug
            //sample_valid_d <= 1'b0;

            candidate    <= 25'd0;
            candidate_sq <= 50'd0;
            sqrt_phase   <= 1'b0;

        end else begin
            rms_valid <= 1'b0;

            case (state)

                // ?? ACCUMULATE ????????????????????????????????????????????????
                S_ACCUMULATE: begin
                    if (sample_valid_d) begin
                        accumulator  <= accumulator + {9'd0, square};
                        sample_count <= sample_count + 8'd1;

                        if (sample_count == 8'd255) begin
                            mean_sq      <= accumulator >> 8; // fixed for pipeline
                            accumulator  <= 57'd0;
                            sample_count <= 8'd0;

                            sqrt_result  <= 25'd0;
                            sqrt_bit     <= 25'h1000000;
                            sqrt_phase   <= 1'b0;

                            state        <= S_SQRT;
                        end
                    end
                end

                // ?? SQRT (PIPELINED) ??????????????????????????????????????????
                S_SQRT: begin
                    if (sqrt_bit != 25'd0) begin

                        if (!sqrt_phase) begin
                            // Stage 1: build candidate
                            candidate  <= sqrt_result | sqrt_bit;
                            sqrt_phase <= 1'b1;
                        end else begin
                            // Stage 2: multiply + compare
                            candidate_sq <= candidate * candidate;

                            if (candidate_sq <= {1'b0, mean_sq}) begin
                                sqrt_result <= candidate;
                            end

                            sqrt_bit   <= sqrt_bit >> 1;
                            sqrt_phase <= 1'b0;
                        end

                    end else begin
                        state <= S_DONE;
                    end
                end

                // ?? DONE ??????????????????????????????????????????????????????
                S_DONE: begin
                    rms_out   <= sqrt_result[23:0];
                    rms_valid <= 1'b1;
                    state     <= S_ACCUMULATE;
                end

                default: state <= S_ACCUMULATE;
            endcase
        end
    end

endmodule

