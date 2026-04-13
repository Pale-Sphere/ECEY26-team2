`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// angle_calc.v
//
// Computes direction-of-arrival angle from 4 microphone RMS log values.
//
//   Y = log2(rms_a) - log2(rms_b)    (one axis)
//   X = log2(rms_c) - log2(rms_d)    (other axis)
//   angle = atan2(Y, X)
//
// Which physical mic is a/b/c/d depends on your wiring at instantiation.
// The module doesn't know or care about compass directions.
//
// Input:  4x 15-bit fixed-point log2 values (5.10 format from log2_block)
//         + valid strobe (all four must be valid simultaneously)
// Output: angle in the CORDIC output format (see below)
//         + valid strobe
//
// CORDIC IP configuration (set these in Vivado IP catalog):
//   - Functional Selection: Translate (Rectangular to Polar)
//   - Architectural Configuration: Word Serial
//   - Pipelining Mode: Optimal
//   - Data Format: Signed Fraction
//   - Phase Format: Radians (or Scaled Radians — your choice)
//   - Input Width: 16 bits (we sign-extend our 15-bit differences to 16)
//   - Output Width: 16 bits
//   - Round Mode: Truncate
//   - Iterations: 0 (auto)
//   - Coarse Rotation: enabled (for full -pi to +pi range)
//
// Instance name in IP catalog: cordic_atan2
//
// The CORDIC "Translate" mode takes Cartesian (X,Y) and outputs:
//   - Phase = atan2(Y, X)
//   - Magnitude = sqrt(X^2 + Y^2) (we ignore this)
//
// Latency: CORDIC pipeline depth (typically 18-20 cycles at 16-bit),
//          plus 2 cycles for subtraction + input registration.
//          At ~190 Hz update rate this is negligible.
//////////////////////////////////////////////////////////////////////////////////

module angle_calc #(
    parameter LOG_WIDTH   = 15,   // 5.10 fixed-point from log2_block
    parameter CORDIC_WIDTH = 16    // CORDIC input/output width
)(
    input  wire                    clk,
    input  wire                    rst,

    // Log2 inputs — from the 4 log2_blocks
    // "a" and "b" are the opposing pair on one axis (Y = a - b)
    // "c" and "d" are the opposing pair on the other axis (X = c - d)
    input  wire [LOG_WIDTH-1:0]    log2_a,
    input  wire [LOG_WIDTH-1:0]    log2_b,
    input  wire [LOG_WIDTH-1:0]    log2_c,
    input  wire [LOG_WIDTH-1:0]    log2_d,
    input  wire                    log2_valid,   // All 4 valid this cycle

    // Zero flags from log2_blocks (input was 0 = silence)
    input  wire                    zero_a,
    input  wire                    zero_b,
    input  wire                    zero_c,
    input  wire                    zero_d,

    // Angle output from CORDIC
    output wire [CORDIC_WIDTH-1:0] angle_out,    // atan2(Y, X), format depends on CORDIC config
    output wire                    angle_valid,

    // Magnitude output (optional — sqrt(X^2+Y^2), can be left unconnected)
    output wire [CORDIC_WIDTH-1:0] magnitude_out
);

    // Stage 1: difference (unchanged)
    reg signed [CORDIC_WIDTH-1:0] y_diff;
    reg signed [CORDIC_WIDTH-1:0] x_diff;
    reg                           diff_valid;

    wire signed [CORDIC_WIDTH-1:0] a_ext = {1'b0, log2_a};
    wire signed [CORDIC_WIDTH-1:0] b_ext = {1'b0, log2_b};
    wire signed [CORDIC_WIDTH-1:0] c_ext = {1'b0, log2_c};
    wire signed [CORDIC_WIDTH-1:0] d_ext = {1'b0, log2_d};

    always @(posedge clk) begin
        if (rst) begin
            y_diff     <= 0;
            x_diff     <= 0;
            diff_valid <= 1'b0;
        end else begin
            diff_valid <= log2_valid;
            if (log2_valid) begin
                y_diff <= a_ext - b_ext;
                x_diff <= c_ext - d_ext;
            end
        end
    end

// ==========================================================
// NEW: Stage 2 - AXI handshake register (CRITICAL FIX)
// ==========================================================

    reg [31:0] cordic_input_reg;
    reg        cordic_valid_reg;

    wire cordic_ready;

    always @(posedge clk) begin
        if (rst) begin
            cordic_valid_reg <= 1'b0;
        end else begin
        // Load new data only when either:
        // 1. No valid data pending, OR
        // 2. CORDIC accepted previous data
        if (!cordic_valid_reg || cordic_ready) begin
            cordic_valid_reg <= diff_valid;
            cordic_input_reg <= {y_diff, x_diff};
            end
        end
    end

// ==========================================================
// CORDIC IP
// ==========================================================

    wire [31:0] cordic_output;
    wire        cordic_output_valid;

    cordic_atan2 cordic_0 (
        .aclk(clk),

        .s_axis_cartesian_tvalid (cordic_valid_reg),
        .s_axis_cartesian_tready (cordic_ready),
        .s_axis_cartesian_tdata  (cordic_input_reg),

        .m_axis_dout_tvalid      (cordic_output_valid),
        .m_axis_dout_tdata       (cordic_output)
    );

// ==========================================================
// Output
// ==========================================================

    assign angle_out     = cordic_output[31:16];
    assign magnitude_out = cordic_output[15:0];
    assign angle_valid   = cordic_output_valid;

endmodule
    