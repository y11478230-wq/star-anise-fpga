`timescale 1ns / 1ps
// Applies the user-confirmed rule to the stable tip count from Python mode 11.
// class_id: 0=八角 (<10), 1=莽草 (>=10), 2=未识别 (invalid frame/target).
module vision_tip_count_classifier (
    input  wire       clk,
    input  wire       resetn,
    input  wire       frame_done,
    input  wire       detector_valid,
    input  wire [7:0] stable_tip_count,
    output reg        result_valid,
    output reg  [1:0] class_id
);
    always @(posedge clk) begin
        if (!resetn) begin
            result_valid <= 1'b0;
            class_id <= 2'd2;
        end else if (frame_done) begin
            if (!detector_valid) begin
                result_valid <= 1'b0;
                class_id <= 2'd2;
            end else begin
                result_valid <= 1'b1;
                class_id <= (stable_tip_count >= 8'd10) ? 2'd1 : 2'd0;
            end
        end
    end
endmodule
