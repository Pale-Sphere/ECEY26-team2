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

    // =========================================================================
    // Stage 1: Compute signed differences (1 cycle)
    //
    // The log2 values are unsigned 5.10 fixed-point.
    // The difference is signed, so we extend to CORDIC_WIDTH (16 bits)
    // which gives us 1 sign + 5.10 = signed 6.10 format.
    //
    // When a mic reads silence (zero_flag), its log is 0. The difference
    // then equals the other mic's log, which is the correct behavior:
    // if one side is silent, the sound is fully from the other side.
    // =========================================================================

    reg signed [CORDIC_WIDTH-1:0] y_diff;  // log2_a - log2_b
    reg signed [CORDIC_WIDTH-1:0] x_diff;  // log2_c - log2_d
    reg                           diff_valid;

    wire signed [CORDIC_WIDTH-1:0] a_ext = {1'b0, log2_a};
    wire signed [CORDIC_WIDTH-1:0] b_ext = {1'b0, log2_b};
    wire signed [CORDIC_WIDTH-1:0] c_ext = {1'b0, log2_c};
    wire signed [CORDIC_WIDTH-1:0] d_ext = {1'b0, log2_d};

    always @(posedge clk or posedge rst) begin
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

    // =========================================================================
    // Stage 2: CORDIC IP — atan2(Y, X)
    //
    // The Xilinx CORDIC IP in Translate mode expects:
    //   s_axis_cartesian_tdata = {Y[15:0], X[15:0]}  (32-bit packed)
    //   s_axis_cartesian_tvalid = 1 when data is ready
    //
    // And outputs:
    //   m_axis_dout_tdata = {PHASE[15:0], MAGNITUDE[15:0]}  (32-bit packed)
    //   m_axis_dout_tvalid = 1 when result is ready
    //
    // NOTE: The exact bit packing depends on your CORDIC IP configuration.
    //       The default for 16-bit Translate mode is:
    //         Input:  [31:16] = Y (imaginary), [15:0] = X (real)
    //         Output: [31:16] = Phase,         [15:0] = Magnitude
    //       Verify this matches your generated IP. Check the IP documentation
    //       or the _stub.v file after generation.
    // =========================================================================

    wire [31:0] cordic_input;
    wire [31:0] cordic_output;
    wire        cordic_input_ready;
    wire        cordic_output_valid;

    // Pack Y (high) and X (low) into CORDIC input
    assign cordic_input = {y_diff, x_diff};

    // Instantiate the Xilinx CORDIC IP
    // You must generate this in Vivado IP Catalog with instance name "cordic_atan2"
    // and the configuration described in the header comment.
    cordic_atan2 cordic_0 (
        .aclk                    (clk),

        // Slave (input) channel
        .s_axis_cartesian_tvalid (diff_valid),
        .s_axis_cartesian_tready (cordic_input_ready),
        .s_axis_cartesian_tdata  (cordic_input),

        // Master (output) channel
        .m_axis_dout_tvalid      (cordic_output_valid),
        .m_axis_dout_tdata       (cordic_output)
    );

    // Unpack CORDIC output
    assign angle_out     = cordic_output[31:16];  // Phase = atan2(Y, X)
    assign magnitude_out = cordic_output[15:0];   // sqrt(X^2 + Y^2)
    assign angle_valid   = cordic_output_valid;

endmodule
