`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// top.v
////////////////////////////////////////////////////////////////////////////////////
// Company: Yale University
// Engineer:  Kemal Okvuran and Evan Losey
// 
// Create Date: 
// Design Name: 
// Module Name: top.v
// Project Name: Francine
// Target Devices: 
// Tool Versions: 
// Description: 
// Full audio direction-of-arrival pipeline:
//   I2S mics → IBUF → I2S receivers → async FIFOs → sample gates
//     → RMS blocks → log2 blocks → synchronizer → angle calculator → angle out
// There are sample gates which I added to discard the first two outputs of the FIFO's which were very wonky for some reason
//things started working after adding them, I'm not too sure why
//
// Clock domains:
//   clk_100mhz  - 100 MHz system clock (Basys 3 W5 oscillator, via MMCM)
//   clk_24mhz/sclk - 24.7 MHz clock output for audio chip
//   bck_0_buf   - BCK from mic pair 0 (via IBUF)
//   bck_1_buf   - BCK from mic pair 1 (via IBUF)
//
// Each I2S mic is stereo (L+R), giving 4 channels total.
// The angle_calc module takes two opposing pairs:
//   axis_a / axis_b → Y = log2(a) - log2(b)
//   axis_c / axis_d → X = log2(c) - log2(d)
//   angle = atan2(Y, X)
//
//
// RMS outputs update every 256 samples (~5.3 ms at 48 kHz).
// Angle updates at the same rate, plus CORDIC pipeline latency (~20 cycles).
//
// SPI Transmitter:
// 
// Dependencies: 
// 
// Revision:
// 
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////
 
module top (
    // Board clock
    input  wire        clock,           // 100 MHz oscillator (Basys 3 pin W5)
 
    // Reset (active high, centre button)
    input  wire        rst_btn,
 
    // Mic pair 0 (I2S)
    input  wire        bck_0,
    input  wire        din_0,
    input  wire        lrck_0,
    output wire        sclk_I2S_0,
 
    // Mic pair 1 (I2S)
    input  wire        bck_1,
    input  wire        din_1,
    input  wire        lrck_1,
    output wire        sclk_I2S_1,
    
    //SPI Transmitter
    input wire sclk_spi,
    input wire ce,
    output wire sdo, //SPI serial data out
    
    //test LEDs
    output wire test
);
 

    wire bck_0_buf, bck_1_buf;
 
    IBUF bck0_ibuf (.I(bck_0), .O(bck_0_buf));
    IBUF bck1_ibuf (.I(bck_1), .O(bck_1_buf));
 
   
    //Clocking Wizard
    wire clk_100mhz;
    wire clk_24mhz;
    wire mmcm_locked;
 
    clk_wiz_0 clk_wiz_inst (
        .clk_in1  (clock),
        .reset    (rst_btn),
        .clk_100MHz (clk_100mhz),
        .clk_24MHz_0 (sclk_I2S_0),
        .clk_24MHz_1 (sclk_I2S_1),
        .locked (mmcm_locked)
    );
 
    // Reset generation
    wire raw_rst = rst_btn | ~mmcm_locked;
 
    // 100 MHz domain
    reg rst_sys_meta, rst_sys;
    always @(posedge clk_100mhz or posedge raw_rst) begin
        if (raw_rst) { rst_sys_meta, rst_sys } <= 2'b11;
        else         { rst_sys_meta, rst_sys } <= {1'b0, rst_sys_meta};
    end
 
    // BCK_0 domain
    reg rst_bck0_meta, rst_bck0;
    always @(posedge bck_0_buf or posedge raw_rst) begin
        if (raw_rst) { rst_bck0_meta, rst_bck0 } <= 2'b11;
        else         { rst_bck0_meta, rst_bck0 } <= {1'b0, rst_bck0_meta};
    end
 
    // BCK_1 domain
    reg rst_bck1_meta, rst_bck1;
    always @(posedge bck_1_buf or posedge raw_rst) begin
        if (raw_rst) { rst_bck1_meta, rst_bck1 } <= 2'b11;
        else         { rst_bck1_meta, rst_bck1 } <= {1'b0, rst_bck1_meta};
    end
 
    //I2S receivers
    //
    wire [23:0] pair0_ldata, pair0_rdata;
    wire [23:0] pair1_ldata, pair1_rdata;
    wire        pair0_sample_ready, pair1_sample_ready;
    assign test = pair0_sample_ready;
 
    I2Sreciever_sample_ready #(.width(24)) i2s_pair0 (
        .bck          (bck_0_buf),
        .din          (din_0),
        .lrck         (lrck_0),
        .rst          (rst_bck0),
        .ldata        (pair0_ldata),
        .rdata        (pair0_rdata),
        .sample_ready (pair0_sample_ready)
    );
 
    I2Sreciever_sample_ready #(.width(24)) i2s_pair1 (
        .bck          (bck_1_buf),
        .din          (din_1),
        .lrck         (lrck_1),
        .rst          (rst_bck1),
        .ldata        (pair1_ldata),
        .rdata        (pair1_rdata),
        .sample_ready (pair1_sample_ready)
    );
 
    // FIFO wiring
    wire p0l_wr_rst_busy, p0l_rd_rst_busy, p0l_full, p0l_empty;
    wire p0r_wr_rst_busy, p0r_rd_rst_busy, p0r_full, p0r_empty;
    wire p1l_wr_rst_busy, p1l_rd_rst_busy, p1l_full, p1l_empty;
    wire p1r_wr_rst_busy, p1r_rd_rst_busy, p1r_full, p1r_empty;
 
    wire [23:0] p0l_dout, p0r_dout, p1l_dout, p1r_dout;
    wire        p0l_valid, p0r_valid, p1l_valid, p1r_valid;
 
    wire p0l_wr_en = pair0_sample_ready & ~p0l_full & ~p0l_wr_rst_busy;
    wire p0r_wr_en = pair0_sample_ready & ~p0r_full & ~p0r_wr_rst_busy;
    wire p1l_wr_en = pair1_sample_ready & ~p1l_full & ~p1l_wr_rst_busy;
    wire p1r_wr_en = pair1_sample_ready & ~p1r_full & ~p1r_wr_rst_busy;
 
    wire p0l_rd_en = ~p0l_empty & ~p0l_rd_rst_busy;
    wire p0r_rd_en = ~p0r_empty & ~p0r_rd_rst_busy;
    wire p1l_rd_en = ~p1l_empty & ~p1l_rd_rst_busy;
    wire p1r_rd_en = ~p1r_empty & ~p1r_rd_rst_busy;
 
    // Unused FIFO ports
    wire p0l_wa, p0r_wa, p1l_wa, p1r_wa;
    wire [9:0] p0l_wc, p0l_rc, p0r_wc, p0r_rc;
    wire [9:0] p1l_wc, p1l_rc, p1r_wc, p1r_rc;
 
    //  FIFO instantiations
    CDC_FIFO fifo_p0l (
        .rst(rst_bck0), .wr_clk(bck_0_buf), .rd_clk(clk_100mhz),
        .din(pair0_ldata), .wr_en(p0l_wr_en), .rd_en(p0l_rd_en),
        .dout(p0l_dout), .full(p0l_full), .empty(p0l_empty),
        .wr_ack(p0l_wa), .valid(p0l_valid),
        .wr_data_count(p0l_wc), .rd_data_count(p0l_rc),
        .wr_rst_busy(p0l_wr_rst_busy), .rd_rst_busy(p0l_rd_rst_busy)
    );
 
    CDC_FIFO fifo_p0r (
        .rst(rst_bck0), .wr_clk(bck_0_buf), .rd_clk(clk_100mhz),
        .din(pair0_rdata), .wr_en(p0r_wr_en), .rd_en(p0r_rd_en),
        .dout(p0r_dout), .full(p0r_full), .empty(p0r_empty),
        .wr_ack(p0r_wa), .valid(p0r_valid),
        .wr_data_count(p0r_wc), .rd_data_count(p0r_rc),
        .wr_rst_busy(p0r_wr_rst_busy), .rd_rst_busy(p0r_rd_rst_busy)
    );
 
    CDC_FIFO fifo_p1l (
        .rst(rst_bck1), .wr_clk(bck_1_buf), .rd_clk(clk_100mhz),
        .din(pair1_ldata), .wr_en(p1l_wr_en), .rd_en(p1l_rd_en),
        .dout(p1l_dout), .full(p1l_full), .empty(p1l_empty),
        .wr_ack(p1l_wa), .valid(p1l_valid),
        .wr_data_count(p1l_wc), .rd_data_count(p1l_rc),
        .wr_rst_busy(p1l_wr_rst_busy), .rd_rst_busy(p1l_rd_rst_busy)
    );
 
    CDC_FIFO fifo_p1r (
        .rst(rst_bck1), .wr_clk(bck_1_buf), .rd_clk(clk_100mhz),
        .din(pair1_rdata), .wr_en(p1r_wr_en), .rd_en(p1r_rd_en),
        .dout(p1r_dout), .full(p1r_full), .empty(p1r_empty),
        .wr_ack(p1r_wa), .valid(p1r_valid),
        .wr_data_count(p1r_wc), .rd_data_count(p1r_rc),
        .wr_rst_busy(p1r_wr_rst_busy), .rd_rst_busy(p1r_rd_rst_busy)
    );
    //honestly these might be symptoms of how I tested it but the fifos kept going wonky initially so I just discarded the first two per ai enabled suggestions
    // Sample gates - discard first 2 spurious samples per channel
    wire [23:0] gated_p0l, gated_p0r, gated_p1l, gated_p1r;
    wire        gated_p0l_valid, gated_p0r_valid;
    wire        gated_p1l_valid, gated_p1r_valid;
 
    sample_gate #(.WIDTH(24), .DISCARD_COUNT(2)) gate_p0l (
        .clk(clk_100mhz), .rst(rst_sys),
        .sample_in(p0l_dout), .sample_valid_in(p0l_valid),
        .sample_out(gated_p0l), .sample_valid_out(gated_p0l_valid)
    );
    sample_gate #(.WIDTH(24), .DISCARD_COUNT(2)) gate_p0r (
        .clk(clk_100mhz), .rst(rst_sys),
        .sample_in(p0r_dout), .sample_valid_in(p0r_valid),
        .sample_out(gated_p0r), .sample_valid_out(gated_p0r_valid)
    );
    sample_gate #(.WIDTH(24), .DISCARD_COUNT(2)) gate_p1l (
        .clk(clk_100mhz), .rst(rst_sys),
        .sample_in(p1l_dout), .sample_valid_in(p1l_valid),
        .sample_out(gated_p1l), .sample_valid_out(gated_p1l_valid)
    );
    sample_gate #(.WIDTH(24), .DISCARD_COUNT(2)) gate_p1r (
        .clk(clk_100mhz), .rst(rst_sys),
        .sample_in(p1r_dout), .sample_valid_in(p1r_valid),
        .sample_out(gated_p1r), .sample_valid_out(gated_p1r_valid)
    );
 
    // 8. RMS blocks - one per channel
    wire [23:0] rms_p0l, rms_p0r, rms_p1l, rms_p1r;
    
    //Testing hardcoding rms values
    wire [23:0] test_p0l = 24'b1; //should output an angle of 90 degrees
    wire [23:0] test_p0r = 24'b0;
    wire [23:0] test_p1l = 24'b0;
    wire [23:0] test_p1r = 24'b0;
    
    wire test_enable0l = 1'b1;
    wire test_enable0r = 1'b1;
    wire test_enable1l = 1'b1;
    wire test_enable1r = 1'b1;
    
    wire        rms_p0l_valid, rms_p0r_valid, rms_p1l_valid, rms_p1r_valid;
    //assign rms_p0r_valid = test;
 
    rms_block rms_p0l_inst (
        .clk(clk_100mhz), .rst(rst_sys),
        .sample_in(test_p0l), .sample_valid(test_enable0l),
        .rms_out(rms_p0l), .rms_valid(rms_p0l_valid)
    );
    rms_block rms_p0r_inst (
        .clk(clk_100mhz), .rst(rst_sys),
        .sample_in(test_p0r), .sample_valid(test_enable0r),
        .rms_out(rms_p0r), .rms_valid(rms_p0r_valid)
    );
    rms_block rms_p1l_inst (
        .clk(clk_100mhz), .rst(rst_sys),
        .sample_in(test_p1l), .sample_valid(test_enable1l),
        .rms_out(rms_p1l), .rms_valid(rms_p1l_valid)
    );
    rms_block rms_p1r_inst (
        .clk(clk_100mhz), .rst(rst_sys),
        .sample_in(test_p1r), .sample_valid(test_enable1r),
        .rms_out(rms_p1r), .rms_valid(rms_p1r_valid)
    );
 
    // Log2 blocks 
    //    15-bit output: 5.10 fixed-point log2 of the 24-bit RMS value
    wire [14:0] log2_p0l, log2_p0r, log2_p1l, log2_p1r;
    wire        log2_p0l_valid, log2_p0r_valid, log2_p1l_valid, log2_p1r_valid;
    wire        log2_p0l_zero, log2_p0r_zero, log2_p1l_zero, log2_p1r_zero;
 
    log2_block #(.INPUT_WIDTH(24), .FRAC_BITS(10)) log_p0l (
        .clk(clk_100mhz), .rst(rst_sys),
        .din(rms_p0l), .din_valid(rms_p0l_valid),
        .log2_out(log2_p0l), .log2_valid(log2_p0l_valid), .zero_flag(log2_p0l_zero)
    );
    log2_block #(.INPUT_WIDTH(24), .FRAC_BITS(10)) log_p0r (
        .clk(clk_100mhz), .rst(rst_sys),
        .din(rms_p0r), .din_valid(rms_p0r_valid),
        .log2_out(log2_p0r), .log2_valid(log2_p0r_valid), .zero_flag(log2_p0r_zero)
    );
    log2_block #(.INPUT_WIDTH(24), .FRAC_BITS(10)) log_p1l (
        .clk(clk_100mhz), .rst(rst_sys),
        .din(rms_p1l), .din_valid(rms_p1l_valid),
        .log2_out(log2_p1l), .log2_valid(log2_p1l_valid), .zero_flag(log2_p1l_zero)
    );
    log2_block #(.INPUT_WIDTH(24), .FRAC_BITS(10)) log_p1r (
        .clk(clk_100mhz), .rst(rst_sys),
        .din(rms_p1r), .din_valid(rms_p1r_valid),
        .log2_out(log2_p1r), .log2_valid(log2_p1r_valid), .zero_flag(log2_p1r_zero)
    );
 
    // Synchronize the 4 log2 valid strobes
    //
    //     The 4 RMS blocks run independently  their valid pulses won't
    //     arrive on the same cycle. latches incoming logs and waits for all 4
    reg [14:0] log2_hold_p0l, log2_hold_p0r, log2_hold_p1l, log2_hold_p1r;
    reg        log2_zero_hold_p0l, log2_zero_hold_p0r;
    reg        log2_zero_hold_p1l, log2_zero_hold_p1r;
    reg [3:0]  log2_arrived;  // [0]=p0l [1]=p0r [2]=p1l [3]=p1r
    reg        all_log2_prev;
 
    wire all_log2_arrived = &log2_arrived;
    wire log2_sync_valid  = all_log2_arrived & ~all_log2_prev;
 
    always @(posedge clk_100mhz or posedge rst_sys) begin
        if (rst_sys) begin
            log2_hold_p0l      <= 0;
            log2_hold_p0r      <= 0;
            log2_hold_p1l      <= 0;
            log2_hold_p1r      <= 0;
            log2_zero_hold_p0l <= 0;
            log2_zero_hold_p0r <= 0;
            log2_zero_hold_p1l <= 0;
            log2_zero_hold_p1r <= 0;
            log2_arrived       <= 4'b0000;
            all_log2_prev      <= 1'b0;
        end else begin
            all_log2_prev <= all_log2_arrived;
 
            // Latch each log2 result as it arrives
            if (log2_p0l_valid) begin
                log2_hold_p0l      <= log2_p0l;
                log2_zero_hold_p0l <= log2_p0l_zero;
                log2_arrived[0]    <= 1'b1;
            end
            if (log2_p0r_valid) begin
                log2_hold_p0r      <= log2_p0r;
                log2_zero_hold_p0r <= log2_p0r_zero;
                log2_arrived[1]    <= 1'b1;
            end
            if (log2_p1l_valid) begin
                log2_hold_p1l      <= log2_p1l;
                log2_zero_hold_p1l <= log2_p1l_zero;
                log2_arrived[2]    <= 1'b1;
            end
            if (log2_p1r_valid) begin
                log2_hold_p1r      <= log2_p1r;
                log2_zero_hold_p1r <= log2_p1r_zero;
                log2_arrived[3]    <= 1'b1;
            end
 
            // Reset arrived flags after sync pulse fires
            if (log2_sync_valid) begin
                log2_arrived <= 4'b0000;
            end
        end
    end
 
    //  Angle calculator
    // Angle output - 16-bit atan2 result + valid strobe
    // Connect to your downstream consumer (UART, display, etc.)
    wire [15:0] magnitude_out;
    wire [15:0] angle_out;
    wire        angle_valid;  
 
    angle_calc #(
        .LOG_WIDTH    (15),
        .CORDIC_WIDTH (16)
    ) angle_inst (
        .clk        (clk_100mhz),
        .rst        (rst_sys),
 
        .log2_a     (log2_hold_p0l),    // Y axis positive
        .log2_b     (log2_hold_p0r),    // Y axis negative
        .log2_c     (log2_hold_p1l),    // X axis positive
        .log2_d     (log2_hold_p1r),    // X axis negative
        .log2_valid (log2_sync_valid),
 
        .zero_a     (log2_zero_hold_p0l),
        .zero_b     (log2_zero_hold_p0r),
        .zero_c     (log2_zero_hold_p1l),
        .zero_d     (log2_zero_hold_p1r),
 
        .angle_out     (angle_out),
        .angle_valid   (angle_valid),
        .magnitude_out (magnitude_out)
    );
 
    //SPI Transmitter
    //Outputs through sdo, ce and sclk_spi control clock
    wire [23:0] theta;
    assign theta = {8'b0, angle_out}; //concatenating 0's with output angle (might have to shift in python code)
    
    spi_tx spi_inst (
    .clk(clk_100mhz),
    .rst(rst_btn),
    .sclk(sclk_spi),
    .ce(ce),
    .sdo(sdo),
    .theta(theta),
    .theta_valid(angle_valid)
);
endmodule