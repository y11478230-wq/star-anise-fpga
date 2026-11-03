`timescale 1ns / 1ps
module camera_status_cdc (
    input wire sys_clk, input wire sys_resetn,
    input wire pclk_heartbeat, input wire overflow_sticky,
    input wire phase_error_sticky, input wire [15:0] overflow_count,
    input wire [15:0] completed_frame_count, input wire [9:0] last_frame_lines,
    input wire [18:0] last_frame_pixels,
    input wire [10:0] min_line_pixels, input wire [10:0] max_line_pixels,
    input wire [9:0] odd_line_count, input wire [31:0] last_frame_pclk_cycles,
    output wire [31:0] status0, output wire [31:0] status1,
    output wire [31:0] diag0, output wire [31:0] diag1
);
    (* ASYNC_REG = "TRUE" *) reg hb_m, hb_s;
    (* ASYNC_REG = "TRUE" *) reg ov_m, ov_s, pe_m, pe_s;
    (* ASYNC_REG = "TRUE" *) reg [15:0] oc_m, oc_s, fc_m, fc_s;
    (* ASYNC_REG = "TRUE" *) reg [9:0] ln_m, ln_s;
    (* ASYNC_REG = "TRUE" *) reg [18:0] px_m, px_s;
    (* ASYNC_REG = "TRUE" *) reg [10:0] min_m, min_s, max_m, max_s;
    (* ASYNC_REG = "TRUE" *) reg [9:0] odd_m, odd_s;
    (* ASYNC_REG = "TRUE" *) reg [31:0] cyc_m, cyc_s;
    reg hb_d, pclk_seen;
    always @(posedge sys_clk) begin
        if (!sys_resetn) begin
            hb_m<=0;hb_s<=0;hb_d<=0;pclk_seen<=0;ov_m<=0;ov_s<=0;pe_m<=0;pe_s<=0;
            oc_m<=0;oc_s<=0;fc_m<=0;fc_s<=0;ln_m<=0;ln_s<=0;px_m<=0;px_s<=0;
            min_m<=0;min_s<=0;max_m<=0;max_s<=0;odd_m<=0;odd_s<=0;cyc_m<=0;cyc_s<=0;
        end else begin
            hb_m<=pclk_heartbeat; hb_s<=hb_m; hb_d<=hb_s;
            if (hb_s != hb_d) pclk_seen<=1;
            ov_m<=overflow_sticky; ov_s<=ov_m; pe_m<=phase_error_sticky; pe_s<=pe_m;
            oc_m<=overflow_count; oc_s<=oc_m; fc_m<=completed_frame_count; fc_s<=fc_m;
            ln_m<=last_frame_lines; ln_s<=ln_m; px_m<=last_frame_pixels; px_s<=px_m;
            min_m<=min_line_pixels; min_s<=min_m; max_m<=max_line_pixels; max_s<=max_m;
            odd_m<=odd_line_count; odd_s<=odd_m;
            cyc_m<=last_frame_pclk_cycles; cyc_s<=cyc_m;
        end
    end
    assign status0 = {px_s, ln_s, pe_s, ov_s, pclk_seen};
    assign status1 = {oc_s, fc_s};
    assign diag0 = {odd_s, min_s, max_s};
    assign diag1 = cyc_s;
endmodule
