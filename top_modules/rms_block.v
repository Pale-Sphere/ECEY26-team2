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

module rms_block (
    input  wire        clk,
    input  wire        rst,

    input  wire signed [23:0] sample_in,
    input  wire               sample_valid,

    output reg  [23:0] rms_out,
    output reg         rms_valid
);

    // ── State machine ─────────────────────────────────────────────────────────
    localparam S_ACCUMULATE = 2'd0;
    localparam S_SQRT       = 2'd1;
    localparam S_DONE       = 2'd2;

    reg [1:0] state;

    // ── Sample counter (0..255) ───────────────────────────────────────────────
    reg [7:0] sample_count;

    // ── Squaring ──────────────────────────────────────────────────────────────
    // Vivado infers a DSP slice for the signed multiply.
    // We square the absolute value to keep the accumulator unsigned.
    wire [23:0]  sample_abs = sample_in[23] ? (~sample_in + 1'b1) : sample_in;
    wire [47:0]  square     = sample_abs * sample_abs;

    // ── Accumulator ───────────────────────────────────────────────────────────
    // 57 bits: 48-bit square + 8 bits for 256 additions + 1 guard bit
    reg [56:0] accumulator;

    // ── Mean of squares (divide by 256 = right shift 8) ──────────────────────
    // Computed once when we leave ACCUMULATE. 49 bits wide.
    reg [48:0] mean_sq;

    // ── Binary search square root ─────────────────────────────────────────────
    // We find the largest integer x such that x² ≤ mean_sq.
    // Method: test each bit from MSB to LSB (25 iterations for 25-bit result).
    reg [24:0] sqrt_result;   // candidate answer being built
    reg [24:0] sqrt_bit;      // current bit being tested (one-hot, shifts right)

    // ── State machine ─────────────────────────────────────────────────────────
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
        end else begin
            rms_valid <= 1'b0;  // default: deassert each cycle

            case (state)

                // ── ACCUMULATE ────────────────────────────────────────────────
                // Wait for valid samples from the FIFO.
                // Add each squared sample to the accumulator.
                // After 256 samples, compute mean and begin sqrt.
                S_ACCUMULATE: begin
                    if (sample_valid) begin
                        accumulator  <= accumulator + {9'd0, square};
                        sample_count <= sample_count + 8'd1;

                        if (sample_count == 8'd255) begin
                            // Window complete — latch mean of squares
                            // Divide by 256: drop the bottom 8 bits
                            mean_sq      <= (accumulator + {9'd0, square}) >> 8;
                            accumulator  <= 57'd0;
                            sample_count <= 8'd0;
                            // Initialise binary search: start from the MSB (bit 24)
                            sqrt_result  <= 25'd0;
                            sqrt_bit     <= 25'h1000000; // bit 24 set
                            state        <= S_SQRT;
                        end
                    end
                end

                // ── SQRT ──────────────────────────────────────────────────────
                // Restoring binary search:
                //   Each cycle test if (sqrt_result | sqrt_bit)² ≤ mean_sq.
                //   If yes, keep the bit set in sqrt_result.
                //   Shift sqrt_bit right by 1 each cycle.
                //   After 25 cycles sqrt_result holds floor(sqrt(mean_sq)).
                S_SQRT: begin
                    if (sqrt_bit != 25'd0) begin
                        // candidate = sqrt_result with current bit set
                        // candidate² = candidate * candidate
                        // Compare to mean_sq (49-bit)
                        // To avoid a 50-bit multiply we note sqrt_result ≤ 2^24,
                        // so candidate fits in 25 bits → candidate² fits in 50 bits.
                        // We use a 50-bit comparison; mean_sq is 49 bits so pad by 1.
                        if (((sqrt_result | sqrt_bit) * (sqrt_result | sqrt_bit))
                                <= {1'b0, mean_sq}) begin
                            sqrt_result <= sqrt_result | sqrt_bit;
                        end
                        sqrt_bit <= sqrt_bit >> 1;
                    end else begin
                        // All 25 bits tested — done
                        state <= S_DONE;
                    end
                end

                // ── DONE ──────────────────────────────────────────────────────
                // Latch the result, pulse rms_valid, return to accumulate.
                S_DONE: begin
                    // sqrt_result is 25 bits; the top bit can only be set if
                    // mean_sq ≥ 2^48, which is impossible (max accumulator /256
                    // with 24-bit samples = (2^23)^2 = 2^46 < 2^48).
                    // Safe to truncate to 24 bits.
                    rms_out   <= sqrt_result[23:0];
                    rms_valid <= 1'b1;
                    state     <= S_ACCUMULATE;
                end

                default: state <= S_ACCUMULATE;
            endcase
        end
    end

endmodule
