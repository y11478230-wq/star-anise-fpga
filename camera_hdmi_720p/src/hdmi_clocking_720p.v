`timescale 1ns / 1ps

// 7-series HDMI clock distribution for a 1280x720p60 TMDS transmitter.
//
// The MMCM supplies one unbuffered 371.25 MHz clock.  BUFIO drives the
// OSERDESE2 high-speed clock and BUFR divides that exact clock by five for
// CLKDIV/video timing.  Keeping both clocks on the same I/O clock tree avoids
// the indeterminate 1x/5x phase relationship that can occur with two BUFGs.
module hdmi_clocking_720p (
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 raw_clk_5x CLK" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME raw_clk_5x, FREQ_HZ 371250000" *)
    input  wire raw_clk_5x,
    input  wire mmcm_locked,

    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 pixel_clk CLK" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME pixel_clk, FREQ_HZ 74250000" *)
    output wire pixel_clk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 serial_clk CLK" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME serial_clk, FREQ_HZ 371250000" *)
    output wire serial_clk,
    output wire ready
);
    wire pixel_clk_i;
    reg [2:0] lock_sync = 3'b000;

    BUFIO serial_clock_buffer (
        .I(raw_clk_5x),
        .O(serial_clk)
    );

    BUFR #(
        .BUFR_DIVIDE("5"),
        .SIM_DEVICE("7SERIES")
    ) pixel_clock_buffer (
        .I(raw_clk_5x),
        .CE(1'b1),
        .CLR(~mmcm_locked),
        .O(pixel_clk_i)
    );

    // Asynchronous assertion, pixel-clock-synchronous release.
    always @(posedge pixel_clk_i or negedge mmcm_locked) begin
        if (!mmcm_locked)
            lock_sync <= 3'b000;
        else
            lock_sync <= {lock_sync[1:0], 1'b1};
    end

    assign pixel_clk = pixel_clk_i;
    assign ready = lock_sync[2];
endmodule
