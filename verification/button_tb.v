`timescale 1ns/1ps
module button_tb;
reg clk=0, resetn=0, frame_done=0, detector_valid=0, button=0;
reg [7:0] count=0;
wire valid, show, latched_valid;
wire [1:0] class_id, latched_class;
always #5 clk=~clk;
vision_tip_count_classifier c(clk,resetn,frame_done,detector_valid,count,valid,class_id);
vision_result_button_latch #(.CLK_HZ(1000),.DEBOUNCE_MS(2)) b(clk,resetn,button,valid,class_id,show,latched_valid,latched_class);
task press; begin button=1; repeat(12) @(negedge clk); button=0; repeat(12) @(negedge clk); end endtask
task frame; input [7:0] n; begin count=n; detector_valid=1; frame_done=1; @(negedge clk); frame_done=0; repeat(3) @(negedge clk); end endtask
initial begin
 repeat(3) @(negedge clk); resetn=1; frame(9); press();
 if(!show || latched_class!=0) $fatal(1,"9 should latch BAJIAO");
 frame(12); if(latched_class!=0) $fatal(1,"result changed while locked");
 press(); if(show) $fatal(1,"second press must show WAIT");
 frame(10); press(); if(!show || latched_class!=1) $fatal(1,"10 should latch MANGCAO");
 $display("BUTTON_CLASS_TEST_PASS"); $finish;
end
endmodule
