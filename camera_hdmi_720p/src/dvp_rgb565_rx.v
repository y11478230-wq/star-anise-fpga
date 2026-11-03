`timescale 1ns / 1ps

// OV5640 DVP RGB565 receiver.  The sensor cannot be back-pressured, so this
// block retains one completed pixel while the asynchronous AXIS FIFO accepts
// it.  A FIFO-full event is explicitly counted; it is never silently treated
// as a valid frame pixel.
module dvp_rgb565_rx #(
    parameter integer FRAME_WIDTH  = 640,
    parameter integer FRAME_HEIGHT = 480,
    parameter integer BYTE_SWAP    = 0,
    parameter integer SAMPLE_NEGEDGE = 0
)(
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 cam_pclk CLK" *)
    // AXIS Data FIFO v2.0 fixes its async S_AXIS metadata at 100 MHz. Keep
    // that metadata here to satisfy IP Integrator; the physical input clock
    // remains independently constrained to 48 MHz in the XDC.
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME cam_pclk, ASSOCIATED_BUSIF M_AXIS, ASSOCIATED_RESET resetn, FREQ_HZ 100000000" *)
    input  wire        cam_pclk,
    input  wire        resetn,
    input  wire        cam_vsync,
    input  wire        cam_href,
    input  wire [7:0]  cam_d,
    output reg  [15:0] m_axis_tdata,
    output reg         m_axis_tvalid,
    input  wire        m_axis_tready,
    output reg         m_axis_tuser,
    output reg         m_axis_tlast,
    output reg         byte_phase,
    output reg         pixel_strobe,
    output reg         overflow_sticky,
    output reg  [15:0] overflow_count,
    output reg         phase_error_sticky,
    output reg  [15:0] completed_frame_count,
    output reg  [9:0]  last_frame_lines,
    output reg  [18:0] last_frame_pixels,
    output reg  [10:0] min_line_pixels,
    output reg  [10:0] max_line_pixels,
    output reg  [9:0]  odd_line_count,
    output reg  [31:0] last_frame_pclk_cycles,
    output reg         pclk_heartbeat
);
    localparam integer FRAME_PIXELS = FRAME_WIDTH * FRAME_HEIGHT;
    reg [7:0] first_byte;
    reg [9:0] x_count, y_count;
    reg [10:0] line_pixels;
    reg [9:0] frame_lines;
    reg [18:0] frame_pixels;
    reg [31:0] frame_pclk_cycles;
    reg [10:0] frame_min_line_pixels, frame_max_line_pixels;
    reg [9:0] frame_odd_line_count;
    reg href_q, vsync_q, frame_valid;
    reg [12:0] heartbeat;
    wire slot_free = !m_axis_tvalid || m_axis_tready;
    wire [15:0] pixel_word = BYTE_SWAP ? {cam_d, first_byte} : {first_byte, cam_d};
    wire capture_clk = SAMPLE_NEGEDGE ? ~cam_pclk : cam_pclk;

    task count_overflow;
        begin
            overflow_sticky <= 1'b1;
            if (overflow_count != 16'hffff)
                overflow_count <= overflow_count + 1'b1;
        end
    endtask

    always @(posedge capture_clk or negedge resetn) begin
        if (!resetn) begin
            first_byte <= 0; byte_phase <= 0; x_count <= 0; y_count <= 0;
            line_pixels <= 0; frame_lines <= 0; frame_pixels <= 0;
            href_q <= 0; vsync_q <= 0; frame_valid <= 0;
            m_axis_tdata <= 0; m_axis_tvalid <= 0; m_axis_tuser <= 0; m_axis_tlast <= 0;
            pixel_strobe <= 0; overflow_sticky <= 0; overflow_count <= 0;
            phase_error_sticky <= 0; completed_frame_count <= 0;
            last_frame_lines <= 0; last_frame_pixels <= 0;
            min_line_pixels <= 0; max_line_pixels <= 0;
            odd_line_count <= 0; last_frame_pclk_cycles <= 0;
            frame_pclk_cycles <= 0;
            frame_min_line_pixels <= 11'h7ff; frame_max_line_pixels <= 0;
            frame_odd_line_count <= 0;
            heartbeat <= 0; pclk_heartbeat <= 0;
        end else begin
            href_q <= cam_href;
            vsync_q <= cam_vsync;
            pixel_strobe <= 1'b0;
            heartbeat <= heartbeat + 1'b1;
            frame_pclk_cycles <= frame_pclk_cycles + 1'b1;
            if (&heartbeat) pclk_heartbeat <= ~pclk_heartbeat;

            if (m_axis_tvalid && m_axis_tready)
                m_axis_tvalid <= 1'b0;

            // Active-high VSYNC: close prior statistics then make a clean SOF.
            if (cam_vsync && !vsync_q) begin
                if (frame_valid) begin
                    completed_frame_count <= completed_frame_count + 1'b1;
                    last_frame_lines <= frame_lines;
                    last_frame_pixels <= frame_pixels;
                    last_frame_pclk_cycles <= frame_pclk_cycles;
                    min_line_pixels <= frame_min_line_pixels;
                    max_line_pixels <= frame_max_line_pixels;
                    odd_line_count <= frame_odd_line_count;
                    if ((frame_lines != FRAME_HEIGHT) || (frame_pixels != FRAME_PIXELS))
                        phase_error_sticky <= 1'b1;
                end
                frame_valid <= 1'b1;
                byte_phase <= 1'b0;
                x_count <= 0; y_count <= 0; line_pixels <= 0;
                frame_lines <= 0; frame_pixels <= 0;
                frame_pclk_cycles <= 32'd1;
                frame_min_line_pixels <= 11'h7ff;
                frame_max_line_pixels <= 0;
                frame_odd_line_count <= 0;
            end else if (cam_vsync) begin
                // Do not let blanking during VSYNC affect a frame counter.
                byte_phase <= 1'b0;
            end else if (cam_href && !href_q) begin
                // The first PCLK with HREF asserted carries the first byte.
                first_byte <= cam_d;
                byte_phase <= 1'b1;
                x_count <= 0;
                line_pixels <= 0;
            end else if (cam_href) begin
                if (!byte_phase) begin
                    first_byte <= cam_d;
                    byte_phase <= 1'b1;
                end else begin
                    byte_phase <= 1'b0;
                    // Ignore the partial sensor frame before the first VSYNC.
                    // It is not a valid AXIS frame and must not poison the
                    // sticky diagnostics or the VDMA frame boundary.
                    if (frame_valid) begin
                        pixel_strobe <= 1'b1;
                        line_pixels <= line_pixels + 1'b1;
                        frame_pixels <= frame_pixels + 1'b1;
                        if ((x_count >= FRAME_WIDTH) || (y_count >= FRAME_HEIGHT))
                            phase_error_sticky <= 1'b1;
                        else if (slot_free) begin
                            m_axis_tdata <= pixel_word;
                            m_axis_tuser <= (x_count == 0) && (y_count == 0);
                            m_axis_tlast <= (x_count == FRAME_WIDTH-1);
                            m_axis_tvalid <= 1'b1;
                        end else begin
                            count_overflow();
                        end
                    end
                    x_count <= x_count + 1'b1;
                end
            end else if (!cam_href && href_q) begin
                // HREF's falling edge is the only line terminator.
                if (frame_valid) begin
                    if (byte_phase || (line_pixels != FRAME_WIDTH))
                        phase_error_sticky <= 1'b1;
                    if (byte_phase && frame_odd_line_count != 10'h3ff)
                        frame_odd_line_count <= frame_odd_line_count + 1'b1;
                    if (line_pixels < frame_min_line_pixels)
                        frame_min_line_pixels <= line_pixels;
                    if (line_pixels > frame_max_line_pixels)
                        frame_max_line_pixels <= line_pixels;
                    if (line_pixels != 0) begin
                        frame_lines <= frame_lines + 1'b1;
                        if (y_count < FRAME_HEIGHT) y_count <= y_count + 1'b1;
                    end
                end
                byte_phase <= 1'b0;
                x_count <= 0;
                line_pixels <= 0;
            end
        end
    end
endmodule
