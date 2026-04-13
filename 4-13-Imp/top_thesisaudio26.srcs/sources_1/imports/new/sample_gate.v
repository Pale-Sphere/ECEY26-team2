`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// sample_gate.v
//
// Suppresses the first DISCARD_COUNT valid samples from a FIFO before passing
// them downstream. Sits between the FIFO output and the RMS block.
//
// After reset, the first DISCARD_COUNT samples with valid=1 are consumed
// (the FIFO is read normally so it doesn't stall) but sample_valid_out
// is held LOW so the RMS block never sees them.
//
// Once DISCARD_COUNT valid samples have been eaten, the gate opens
// permanently and all subsequent samples pass through unchanged.
//////////////////////////////////////////////////////////////////////////////////

module sample_gate #(
    parameter WIDTH         = 24,
    parameter DISCARD_COUNT = 2    // Number of initial samples to suppress
)(
    input  wire             clk,
    input  wire             rst,

    // From FIFO
    input  wire [WIDTH-1:0] sample_in,
    input  wire             sample_valid_in,

    // To RMS block
    output wire [WIDTH-1:0] sample_out,
    output wire             sample_valid_out
);

    // Counter only needs enough bits to count to DISCARD_COUNT
    localparam CNT_W = $clog2(DISCARD_COUNT + 1);

    reg [CNT_W-1:0] discard_cnt;
    reg              gate_open;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            discard_cnt <= 0;
            gate_open   <= 1'b0;
        end else if (!gate_open && sample_valid_in) begin
            if (discard_cnt == DISCARD_COUNT - 1) begin
                discard_cnt <= discard_cnt + 1;
                gate_open   <= 1'b1;       // Opens on the NEXT valid sample
            end else begin
                discard_cnt <= discard_cnt + 1;
            end
        end
    end

    // Data passes through unchanged; only valid is gated
    assign sample_out       = sample_in;
    assign sample_valid_out = sample_valid_in & gate_open;

endmodule
