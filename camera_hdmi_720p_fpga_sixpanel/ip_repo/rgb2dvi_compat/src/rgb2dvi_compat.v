`timescale 1ns / 1ps
// Fixed-clock external-serial-clock implementation of the Digilent rgb2dvi
// data path.  It uses the same RGB/native-video and reset topology as the
// PYNQ-Z1 Base overlay, but is source-local because Vivado itself does not
// ship the Digilent IP repository.
module rgb2dvi_compat (
    input wire PixelClk, input wire SerialClk, input wire aRst_n,
    input wire [23:0] vid_pData, input wire vid_pVDE,
    input wire vid_pHSync, input wire vid_pVSync,
    (* X_INTERFACE_INFO = "xilinx.com:signal:data:1.0 TMDS_Clk_p DATA" *)
    output wire TMDS_Clk_p,
    (* X_INTERFACE_INFO = "xilinx.com:signal:data:1.0 TMDS_Clk_n DATA" *)
    output wire TMDS_Clk_n,
    output wire [2:0] TMDS_Data_p, output wire [2:0] TMDS_Data_n
);
    // Match the Digilent reset bridge: assert immediately when the clock is
    // not valid and release only on PixelClk edges.  Releasing OSERDES reset
    // asynchronously can leave the master/slave pair out of word alignment.
    reg [3:0] reset_pipe = 4'hf;
    always @(posedge PixelClk or negedge aRst_n) begin
        if (!aRst_n)
            reset_pipe <= 4'hf;
        else
            reset_pipe <= {reset_pipe[2:0], 1'b0};
    end
    wire rst = reset_pipe[3];
    wire [9:0] c0 = 10'b1111100000;
    wire [9:0] b, g, r;
    // rgb565_to_rgb888_axis emits B,G,R from MSB to LSB.  Keep the TMDS
    // channels aligned with the existing PYNQ-Z1 dvi_tx implementation.
    tmds_encoder_compat e0(.clk(PixelClk),.rst(rst),.d(vid_pData[23:16]),.c({vid_pVSync,vid_pHSync}),.de(vid_pVDE),.q(b));
    tmds_encoder_compat e1(.clk(PixelClk),.rst(rst),.d(vid_pData[15:8]),.c(0),.de(vid_pVDE),.q(g));
    tmds_encoder_compat e2(.clk(PixelClk),.rst(rst),.d(vid_pData[7:0]),.c(0),.de(vid_pVDE),.q(r));
    oserdes10_compat s0(.pixel_clk(PixelClk),.serial_clk(SerialClk),.rst(rst),.d(c0),.p(TMDS_Clk_p),.n(TMDS_Clk_n));
    oserdes10_compat s1(.pixel_clk(PixelClk),.serial_clk(SerialClk),.rst(rst),.d(b),.p(TMDS_Data_p[0]),.n(TMDS_Data_n[0]));
    oserdes10_compat s2(.pixel_clk(PixelClk),.serial_clk(SerialClk),.rst(rst),.d(g),.p(TMDS_Data_p[1]),.n(TMDS_Data_n[1]));
    oserdes10_compat s3(.pixel_clk(PixelClk),.serial_clk(SerialClk),.rst(rst),.d(r),.p(TMDS_Data_p[2]),.n(TMDS_Data_n[2]));
endmodule

module tmds_encoder_compat(input wire clk,input wire rst,input wire [7:0] d,input wire [1:0] c,input wire de,output reg [9:0] q);
    integer i, ones_d, ones_qm, balance;
    reg [8:0] qm; reg xnor_mode; reg signed [5:0] disparity;
    always @* begin
        ones_d=d[0]+d[1]+d[2]+d[3]+d[4]+d[5]+d[6]+d[7];
        xnor_mode=(ones_d>4)||((ones_d==4)&&!d[0]); qm[0]=d[0];
        for(i=1;i<8;i=i+1) qm[i]=xnor_mode ? ~(qm[i-1]^d[i]) : (qm[i-1]^d[i]);
        qm[8]=!xnor_mode; ones_qm=qm[0]+qm[1]+qm[2]+qm[3]+qm[4]+qm[5]+qm[6]+qm[7];
        balance=ones_qm*2-8;
    end
    always @(posedge clk) begin
      if(rst) begin q<=10'b1101010100; disparity<=0; end
      else if(!de) begin disparity<=0; case(c)
        0:q<=10'b1101010100; 1:q<=10'b0010101011; 2:q<=10'b0101010100; default:q<=10'b1010101011; endcase end
      else if((disparity==0)||(balance==0)) begin
        q<={~qm[8],qm[8],qm[8]?qm[7:0]:~qm[7:0]};
        // For a balanced symbol the previous running disparity must be
        // retained.  The old implementation incorrectly forced it to zero.
        disparity<=disparity+(qm[8]?balance:-balance);
      end
      else if(((disparity>0)&&(balance>0))||((disparity<0)&&(balance<0))) begin q<={1'b1,qm[8],~qm[7:0]}; disparity<=disparity+(qm[8]?2:0)-balance; end
      else begin q<={1'b0,qm[8],qm[7:0]}; disparity<=disparity-(qm[8]?0:2)+balance; end
    end
endmodule

module oserdes10_compat(input wire pixel_clk,input wire serial_clk,input wire rst,input wire [9:0] d,output wire p,output wire n);
    wire sd, sh1, sh2;
    OSERDESE2 #(.DATA_RATE_OQ("DDR"),.DATA_RATE_TQ("SDR"),.DATA_WIDTH(10),.SERDES_MODE("MASTER"),.TRISTATE_WIDTH(1)) master(
      .OQ(sd),.CLK(serial_clk),.CLKDIV(pixel_clk),.D1(d[0]),.D2(d[1]),.D3(d[2]),.D4(d[3]),.D5(d[4]),.D6(d[5]),.D7(d[6]),.D8(d[7]),.OCE(1'b1),.RST(rst),.SHIFTIN1(sh1),.SHIFTIN2(sh2),.T1(0),.T2(0),.T3(0),.T4(0),.TCE(0),.TBYTEIN(0),.OFB(),.TBYTEOUT(),.TFB(),.TQ(),.SHIFTOUT1(),.SHIFTOUT2());
    OSERDESE2 #(.DATA_RATE_OQ("DDR"),.DATA_RATE_TQ("SDR"),.DATA_WIDTH(10),.SERDES_MODE("SLAVE"),.TRISTATE_WIDTH(1)) slave(
      .OQ(),.CLK(serial_clk),.CLKDIV(pixel_clk),.D1(0),.D2(0),.D3(d[8]),.D4(d[9]),.D5(0),.D6(0),.D7(0),.D8(0),.OCE(1'b1),.RST(rst),.SHIFTIN1(0),.SHIFTIN2(0),.SHIFTOUT1(sh1),.SHIFTOUT2(sh2),.T1(0),.T2(0),.T3(0),.T4(0),.TCE(0),.TBYTEIN(0),.OFB(),.TBYTEOUT(),.TFB(),.TQ());
    OBUFDS #(.IOSTANDARD("TMDS_33"),.SLEW("FAST")) outbuf(.I(sd),.O(p),.OB(n));
endmodule
