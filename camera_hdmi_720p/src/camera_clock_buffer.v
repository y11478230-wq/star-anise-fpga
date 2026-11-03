`timescale 1ns / 1ps
// U18 is a non clock-capable Pmod pin.  The accompanying XDC intentionally
// permits the dedicated-route exception; the BUFG is still required so every
// DVP register sees the same clock tree.
module camera_clock_buffer(input wire cam_pclk, output wire cam_pclk_buf);
    wire pclk_ibuf;
    IBUF u_ibuf (.I(cam_pclk), .O(pclk_ibuf));
    BUFG u_bufg (.I(pclk_ibuf), .O(cam_pclk_buf));
endmodule
