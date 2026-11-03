`timescale 1ns / 1ps

// Place an unscaled 640x480 RGB565 AXI stream in the center of 720p timing.
// The stream is consumed once per HDMI frame and parked at its next SOF.
module hdmi_vga_axis_raster #(
    parameter integer COMPARE_MODE = 0,
    parameter integer SIX_PANEL_MODE = 0
) (
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 pixel_clk CLK" *)
    (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME pixel_clk, ASSOCIATED_BUSIF S_AXIS, ASSOCIATED_RESET resetn, FREQ_HZ 74250000" *)
    input wire pixel_clk,
    input wire resetn,
    input wire [15:0] s_axis_tdata,
    input wire s_axis_tvalid,
    output wire s_axis_tready,
    input wire s_axis_tuser,
    input wire s_axis_tlast,
    input wire box_enable,
    input wire [9:0] box_x0,
    input wire [9:0] box_x1,
    input wire [8:0] box_y0,
    input wire [8:0] box_y1,
    input wire result_valid,
    input wire result_class,
    input wire result_invalid,
    output reg [23:0] pixel_data = 24'd0,
    output reg data_enable = 1'b0,
    output reg hsync_n = 1'b1,
    output reg vsync_n = 1'b1,
    output wire [31:0] status0,
    output wire [31:0] status1
);
    localparam H_ACTIVE = 1280;
    localparam H_TOTAL = 1650;
    localparam H_SYNC_START = 1390;
    localparam H_SYNC_END = 1430;
    localparam V_ACTIVE = 720;
    localparam V_TOTAL = 750;
    localparam V_SYNC_START = 725;
    localparam V_SYNC_END = 730;
    localparam SEARCH = 2'd0;
    localparam WAIT_FRAME = 2'd1;
    localparam ACTIVE = 2'd2;

    reg [10:0] x = 0;
    reg [9:0] y = 0;
    reg [1:0] state = SEARCH;
    reg [15:0] pending_pixel = 0;
    reg [15:0] displayed_frames = 0;
    reg [15:0] underflow_count = 0;
    reg [15:0] frame_nonzero_samples = 0;
    reg [15:0] last_nonzero_samples = 0;
    reg sync_error_sticky = 1'b0;
    reg underflow_sticky = 1'b0;
    reg box_enable_frame = 1'b0;
    reg [9:0] box_x0_frame = 0, box_x1_frame = 0;
    reg [8:0] box_y0_frame = 0, box_y1_frame = 0;
    (* ASYNC_REG = "TRUE" *) reg result_valid_meta = 1'b0;
    (* ASYNC_REG = "TRUE" *) reg result_valid_sync = 1'b0;
    (* ASYNC_REG = "TRUE" *) reg result_class_meta = 1'b0;
    (* ASYNC_REG = "TRUE" *) reg result_class_sync = 1'b0;
    (* ASYNC_REG = "TRUE" *) reg result_invalid_meta = 1'b0;
    (* ASYNC_REG = "TRUE" *) reg result_invalid_sync = 1'b0;
    reg result_valid_frame = 1'b0;
    reg result_class_frame = 1'b0;
    reg result_invalid_frame = 1'b0;

    wire in_image = SIX_PANEL_MODE ?
                    ((x < 11'd1280) && (y < 10'd640)) :
                    (COMPARE_MODE ?
                    ((x < 11'd1280) && (y >= 10'd120) && (y < 10'd600)) :
                    ((x >= 11'd320) && (x < 11'd960) &&
                     (y >= 10'd120) && (y < 10'd600)));
    wire first_image = SIX_PANEL_MODE ?
                       ((x == 11'd0) && (y == 10'd0)) :
                       (COMPARE_MODE ?
                       ((x == 11'd0) && (y == 10'd120)) :
                       ((x == 11'd320) && (y == 10'd120)));
    wire last_image = SIX_PANEL_MODE ?
                      ((x == 11'd1279) && (y == 10'd639)) :
                      (COMPARE_MODE ?
                      ((x == 11'd1279) && (y == 10'd599)) :
                      ((x == 11'd959) && (y == 10'd599)));
    wire last_column = (SIX_PANEL_MODE || COMPARE_MODE) ?
                       (x == 11'd1279) : (x == 11'd959);
    wire [10:0] image_x_wide = SIX_PANEL_MODE ? x : (COMPARE_MODE ?
                               ((x < 11'd640) ? x : x - 11'd640) :
                               (x - 11'd320));
    wire [9:0] image_x = image_x_wide[9:0];
    wire [8:0] image_y = y - 10'd120;
    wire inside_box = (image_x >= box_x0_frame) &&
                      (image_x < box_x1_frame) &&
                      (image_y >= box_y0_frame) &&
                      (image_y < box_y1_frame);
    wire box_edge = ((image_x - box_x0_frame) < 10'd2) ||
                    ((box_x1_frame - 10'd1 - image_x) < 10'd2) ||
                    ((image_y - box_y0_frame) < 9'd2) ||
                    ((box_y1_frame - 9'd1 - image_y) < 9'd2);
    wire draw_box = !SIX_PANEL_MODE && box_enable_frame && in_image && inside_box && box_edge;
    wire in_result_panel = SIX_PANEL_MODE ?
                           ((x < 11'd1280) && (y >= 10'd640) && (y < 10'd720)) :
                           ((x >= 11'd992) && (x < 11'd1280) &&
                            (y >= 10'd640) && (y < 10'd720));
    wire [7:0] label_dx = x - 11'd1008;
    wire [6:0] label_dy = y - 10'd666;
    wire in_label = (x >= 11'd1008) && (x < 11'd1232) &&
                    (y >= 10'd666) && (y < 10'd694);
    wire [2:0] label_index = label_dx[7:5];
    wire [2:0] glyph_column = label_dx[4:2];
    wire [2:0] glyph_row_index = label_dy[4:2];
    wire [7:0] label_character = result_valid_frame ?
        class_character(result_class_frame, label_index) : wait_character(label_index);
    wire [4:0] glyph_pixels = glyph_row(label_character, glyph_row_index);
    wire draw_ascii_label = in_label && (glyph_column < 5) &&
                            glyph_pixels[4 - glyph_column];
    wire [6:0] cjk_dx = x - 11'd1120;
    wire [5:0] cjk_dy = y - 10'd664;
    wire in_cjk_label = (x >= 11'd1120) && (x < 11'd1184) &&
                        (y >= 10'd664) && (y < 10'd696);
    wire [15:0] cjk_pixels = cjk_glyph_row(result_class_frame, cjk_dx[5],
                                             cjk_dy[4:1]);
    wire draw_cjk_label = in_cjk_label && result_valid_frame && !result_invalid_frame &&
                          cjk_pixels[15 - cjk_dx[4:1]];
    wire [7:0] invalid_dx = x - 11'd1088;
    wire [2:0] invalid_index = invalid_dx[6:5];
    wire [2:0] invalid_column = invalid_dx[4:2];
    wire [7:0] invalid_character = missing_character(invalid_index);
    wire [4:0] invalid_glyph_pixels = glyph_row(invalid_character, glyph_row_index);
    wire draw_invalid_label = (x >= 11'd1088) && (x < 11'd1216) &&
                              (y >= 10'd666) && (y < 10'd694) &&
                              (invalid_column < 5) &&
                              invalid_glyph_pixels[4 - invalid_column];
    wire draw_label = SIX_PANEL_MODE ?
        (!result_valid_frame ? draw_ascii_label : (result_invalid_frame ? draw_invalid_label : draw_cjk_label)) :
        draw_ascii_label;
    wire [1:0] tile_col = x < 426 ? 0 : (x < 853 ? 1 : 2);
    wire [10:0] tile_origin = tile_col == 0 ? 0 : (tile_col == 1 ? 426 : 853);
    wire [10:0] title_x = x - tile_origin - 8;
    wire [9:0] title_y = y < 320 ? y : y - 320;
    wire title_area = SIX_PANEL_MODE && y < 640 && title_y >= 300 && title_y < 318 && x >= tile_origin+8 && title_x < 192;
    wire [4:0] title_index = title_x / 12;
    wire [3:0] title_col = (title_x % 12) >> 1;
    wire [2:0] title_row = (title_y - 300) >> 1;
    wire [2:0] title_tile = (y >= 320 ? 3 : 0) + tile_col;
    wire [7:0] title_char = panel_title(title_tile, title_index);
    wire [4:0] title_pixels = glyph_row(title_char,title_row);
    wire draw_title = title_area && title_col < 5 && title_pixels[4-title_col];
    wire in_compare_banner = !SIX_PANEL_MODE && COMPARE_MODE &&
                             (y >= 10'd32) && (y < 10'd60) &&
                             (((x >= 11'd16) && (x < 11'd144)) ||
                              ((x >= 11'd656) && (x < 11'd816)));
    wire [7:0] compare_label_dx = (x < 11'd640) ? x - 11'd16 : x - 11'd656;
    wire [2:0] compare_label_index = compare_label_dx[7:5];
    wire [2:0] compare_glyph_column = compare_label_dx[4:2];
    wire [2:0] compare_glyph_row = (y - 10'd32) >> 2;
    wire [7:0] compare_label_character = (x < 11'd640) ?
        original_character(compare_label_index) : processed_character(compare_label_index);
    wire [4:0] compare_glyph_pixels = glyph_row(compare_label_character,
                                                 compare_glyph_row);
    wire draw_compare_label = in_compare_banner && (compare_glyph_column < 5) &&
                              compare_glyph_pixels[4 - compare_glyph_column];
    assign s_axis_tready = resetn && ((state == SEARCH) ||
                                       ((state == ACTIVE) && in_image));
    // Sample one pixel in each 16x16 block to distinguish black video from
    // a valid camera stream without storing or exporting full image data.
    assign status0 = {last_nonzero_samples, displayed_frames};
    assign status1 = {underflow_count, 12'd0, sync_error_sticky, underflow_sticky,
                      (state != SEARCH), resetn};

    function [23:0] rgb565_to_rgb;
        input [15:0] pixel;
        reg [4:0] red;
        reg [5:0] green;
        reg [4:0] blue;
        begin
            red = pixel[15:11];
            green = pixel[10:5];
            blue = pixel[4:0];
            rgb565_to_rgb = {{red, red[4:2]},
                             {green, green[5:4]},
                             {blue, blue[4:2]}};
        end
    endfunction

    function [7:0] panel_title;
        input [2:0] tile;
        input [4:0] index;
        reg [127:0] chars;
        begin
            case(tile)
                0: chars="ORIGINAL        ";
                1: chars="MASK EDGE       ";
                2: chars="FILL LIGHT      ";
                3: chars="FILLED MASK     ";
                4: chars="TIP CANDIDATES  ";
                default: chars="TIP COUNT       ";
            endcase
            if(index < 16) panel_title=chars[127-index*8 -: 8];
            else panel_title=0;
        end
    endfunction

    function [7:0] class_character;
        input class_id;
        input [2:0] index;
        begin
            class_character = 8'd0;
            if (!class_id) begin
                case (index)
                    0: class_character = "B";
                    1: class_character = "A";
                    2: class_character = "J";
                    3: class_character = "I";
                    4: class_character = "A";
                    5: class_character = "O";
                    default: class_character = 8'd0;
                endcase
            end else begin
                case (index)
                    0: class_character = "M";
                    1: class_character = "A";
                    2: class_character = "N";
                    3: class_character = "G";
                    4: class_character = "C";
                    5: class_character = "A";
                    6: class_character = "O";
                    default: class_character = 8'd0;
                endcase
            end
        end
    endfunction

    function [7:0] wait_character;
        input [2:0] index;
        begin
            case (index)
                0: wait_character = "W";
                1: wait_character = "A";
                2: wait_character = "I";
                3: wait_character = "T";
                default: wait_character = 8'd0;
            endcase
        end
    endfunction

    function [7:0] missing_character;
        input [2:0] index;
        begin
            case (index)
                0: missing_character = "N";
                1: missing_character = "O";
                2: missing_character = "N";
                3: missing_character = "E";
                default: missing_character = 8'd0;
            endcase
        end
    endfunction

    // 16x16 glyphs for 八角 and 莽草.
    function [15:0] cjk_glyph_row;
        input class_id;
        input glyph_index;
        input [3:0] row_index;
        begin
            cjk_glyph_row = 16'h0000;
            case ({class_id, glyph_index})
                2'b00: case (row_index)
                    0: cjk_glyph_row=16'h0000; 1: cjk_glyph_row=16'h0000;
                    2: cjk_glyph_row=16'h0000; 3: cjk_glyph_row=16'h0000;
                    4: cjk_glyph_row=16'h0460; 5: cjk_glyph_row=16'h0460;
                    6: cjk_glyph_row=16'h0460; 7: cjk_glyph_row=16'h0C60;
                    8: cjk_glyph_row=16'h0C20; 9: cjk_glyph_row=16'h0C20;
                    10: cjk_glyph_row=16'h0C30; 11: cjk_glyph_row=16'h0830;
                    12: cjk_glyph_row=16'h1810; 13: cjk_glyph_row=16'h1018;
                    14: cjk_glyph_row=16'h3008; 15: cjk_glyph_row=16'h600C;
                endcase
                2'b01: case (row_index)
                    0: cjk_glyph_row=16'h0000; 1: cjk_glyph_row=16'h0000;
                    2: cjk_glyph_row=16'h0000; 3: cjk_glyph_row=16'h0C00;
                    4: cjk_glyph_row=16'h0FF0; 5: cjk_glyph_row=16'h1830;
                    6: cjk_glyph_row=16'h3060; 7: cjk_glyph_row=16'h7FFE;
                    8: cjk_glyph_row=16'h7186; 9: cjk_glyph_row=16'h3086;
                    10: cjk_glyph_row=16'h3FFE; 11: cjk_glyph_row=16'h3186;
                    12: cjk_glyph_row=16'h3086; 13: cjk_glyph_row=16'h3FFE;
                    14: cjk_glyph_row=16'h2186; 15: cjk_glyph_row=16'h6086;
                endcase
                2'b10: case (row_index)
                    0: cjk_glyph_row=16'h0000; 1: cjk_glyph_row=16'h0410;
                    2: cjk_glyph_row=16'h7FFF; 3: cjk_glyph_row=16'h0490;
                    4: cjk_glyph_row=16'h010C; 5: cjk_glyph_row=16'h3FFE;
                    6: cjk_glyph_row=16'h0340; 7: cjk_glyph_row=16'h0C30;
                    8: cjk_glyph_row=16'h741F; 9: cjk_glyph_row=16'h0410;
                    10: cjk_glyph_row=16'h7FFF; 11: cjk_glyph_row=16'h0410;
                    12: cjk_glyph_row=16'h0C10; 13: cjk_glyph_row=16'h1810;
                    14: cjk_glyph_row=16'h3010; 15: cjk_glyph_row=16'h0000;
                endcase
                2'b11: case (row_index)
                    0: cjk_glyph_row=16'h0000; 1: cjk_glyph_row=16'h0000;
                    2: cjk_glyph_row=16'h0000; 3: cjk_glyph_row=16'h0420;
                    4: cjk_glyph_row=16'hFFFF; 5: cjk_glyph_row=16'h0420;
                    6: cjk_glyph_row=16'h0020; 7: cjk_glyph_row=16'h3FFC;
                    8: cjk_glyph_row=16'h300C; 9: cjk_glyph_row=16'h3FFC;
                    10: cjk_glyph_row=16'h300C; 11: cjk_glyph_row=16'h3FFC;
                    12: cjk_glyph_row=16'h318C; 13: cjk_glyph_row=16'h0180;
                    14: cjk_glyph_row=16'hFFFF; 15: cjk_glyph_row=16'h0180;
                endcase
            endcase
        end
    endfunction

    function [7:0] original_character;
        input [2:0] index;
        begin
            case (index)
                0: original_character = "O";
                1: original_character = "R";
                2: original_character = "I";
                3: original_character = "G";
                default: original_character = 8'd0;
            endcase
        end
    endfunction

    function [7:0] processed_character;
        input [2:0] index;
        begin
            case (index)
                0: processed_character = "P";
                1: processed_character = "R";
                2: processed_character = "O";
                3: processed_character = "C";
                default: processed_character = 8'd0;
            endcase
        end
    endfunction

    function [4:0] glyph_row;
        input [7:0] character;
        input [2:0] row_index;
        begin
            glyph_row = 5'b00000;
            case (character)
                "A": case (row_index)
                    0: glyph_row = 5'b01110; 1: glyph_row = 5'b10001;
                    2: glyph_row = 5'b10001; 3: glyph_row = 5'b11111;
                    4: glyph_row = 5'b10001; 5: glyph_row = 5'b10001;
                    6: glyph_row = 5'b10001; default: glyph_row = 5'b00000;
                endcase
                "B": case (row_index)
                    0: glyph_row = 5'b11110; 1: glyph_row = 5'b10001;
                    2: glyph_row = 5'b10001; 3: glyph_row = 5'b11110;
                    4: glyph_row = 5'b10001; 5: glyph_row = 5'b10001;
                    6: glyph_row = 5'b11110; default: glyph_row = 5'b00000;
                endcase
                "C": case (row_index)
                    0: glyph_row = 5'b01111; 1: glyph_row = 5'b10000;
                    2: glyph_row = 5'b10000; 3: glyph_row = 5'b10000;
                    4: glyph_row = 5'b10000; 5: glyph_row = 5'b10000;
                    6: glyph_row = 5'b01111; default: glyph_row = 5'b00000;
                endcase
                "G": case (row_index)
                    0: glyph_row = 5'b01111; 1: glyph_row = 5'b10000;
                    2: glyph_row = 5'b10000; 3: glyph_row = 5'b10111;
                    4: glyph_row = 5'b10001; 5: glyph_row = 5'b10001;
                    6: glyph_row = 5'b01111; default: glyph_row = 5'b00000;
                endcase
                "I": case (row_index)
                    0: glyph_row = 5'b11111; 1: glyph_row = 5'b00100;
                    2: glyph_row = 5'b00100; 3: glyph_row = 5'b00100;
                    4: glyph_row = 5'b00100; 5: glyph_row = 5'b00100;
                    6: glyph_row = 5'b11111; default: glyph_row = 5'b00000;
                endcase
                "J": case (row_index)
                    0: glyph_row = 5'b00111; 1: glyph_row = 5'b00010;
                    2: glyph_row = 5'b00010; 3: glyph_row = 5'b00010;
                    4: glyph_row = 5'b10010; 5: glyph_row = 5'b10010;
                    6: glyph_row = 5'b01100; default: glyph_row = 5'b00000;
                endcase
                "M": case (row_index)
                    0: glyph_row = 5'b10001; 1: glyph_row = 5'b11011;
                    2: glyph_row = 5'b10101; 3: glyph_row = 5'b10101;
                    4: glyph_row = 5'b10001; 5: glyph_row = 5'b10001;
                    6: glyph_row = 5'b10001; default: glyph_row = 5'b00000;
                endcase
                "N": case (row_index)
                    0: glyph_row = 5'b10001; 1: glyph_row = 5'b11001;
                    2: glyph_row = 5'b10101; 3: glyph_row = 5'b10011;
                    4: glyph_row = 5'b10001; 5: glyph_row = 5'b10001;
                    6: glyph_row = 5'b10001; default: glyph_row = 5'b00000;
                endcase
                "O": case (row_index)
                    0: glyph_row = 5'b01110; 1: glyph_row = 5'b10001;
                    2: glyph_row = 5'b10001; 3: glyph_row = 5'b10001;
                    4: glyph_row = 5'b10001; 5: glyph_row = 5'b10001;
                    6: glyph_row = 5'b01110; default: glyph_row = 5'b00000;
                endcase
                "L": case (row_index)
                    0: glyph_row = 5'b10000; 1: glyph_row = 5'b10000;
                    2: glyph_row = 5'b10000; 3: glyph_row = 5'b10000;
                    4: glyph_row = 5'b10000; 5: glyph_row = 5'b10000;
                    6: glyph_row = 5'b11111; default: glyph_row = 5'b00000;
                endcase
                "R": case (row_index)
                    0: glyph_row = 5'b11110; 1: glyph_row = 5'b10001;
                    2: glyph_row = 5'b10001; 3: glyph_row = 5'b11110;
                    4: glyph_row = 5'b10100; 5: glyph_row = 5'b10010;
                    6: glyph_row = 5'b10001; default: glyph_row = 5'b00000;
                endcase
                "T": case (row_index)
                    0: glyph_row = 5'b11111; 1: glyph_row = 5'b00100;
                    2: glyph_row = 5'b00100; 3: glyph_row = 5'b00100;
                    4: glyph_row = 5'b00100; 5: glyph_row = 5'b00100;
                    6: glyph_row = 5'b00100; default: glyph_row = 5'b00000;
                endcase
                "W": case (row_index)
                    0: glyph_row = 5'b10001; 1: glyph_row = 5'b10001;
                    2: glyph_row = 5'b10001; 3: glyph_row = 5'b10101;
                    4: glyph_row = 5'b10101; 5: glyph_row = 5'b10101;
                    6: glyph_row = 5'b01010; default: glyph_row = 5'b00000;
                endcase
                "D": case(row_index) 0:glyph_row=5'b11110; 1,2,3,4,5:glyph_row=5'b10001; 6:glyph_row=5'b11110; default:glyph_row=0; endcase
                "E": case(row_index) 0,3,6:glyph_row=5'b11111; 1,2,4,5:glyph_row=5'b10000; default:glyph_row=0; endcase
                "F": case(row_index) 0,3:glyph_row=5'b11111; 1,2,4,5,6:glyph_row=5'b10000; default:glyph_row=0; endcase
                "H": case(row_index) 3:glyph_row=5'b11111; 0,1,2,4,5,6:glyph_row=5'b10001; default:glyph_row=0; endcase
                "K": case(row_index) 0,6:glyph_row=5'b10001; 1,5:glyph_row=5'b10010; 2,4:glyph_row=5'b10100; 3:glyph_row=5'b11000; default:glyph_row=0; endcase
                "P": case(row_index) 0,3:glyph_row=5'b11110; 1,2:glyph_row=5'b10001; 4,5,6:glyph_row=5'b10000; default:glyph_row=0; endcase
                "S": case(row_index) 0,3,6:glyph_row=5'b01111; 1,2:glyph_row=5'b10000; 4,5:glyph_row=5'b00001; default:glyph_row=0; endcase
                "U": case(row_index) 0,1,2,3,4,5:glyph_row=5'b10001; 6:glyph_row=5'b01110; default:glyph_row=0; endcase
                default: glyph_row = 5'b00000;
            endcase
        end
    endfunction

    always @(posedge pixel_clk) begin
        if (!resetn) begin
            x <= 0;
            y <= 0;
            state <= SEARCH;
            pending_pixel <= 0;
            displayed_frames <= 0;
            underflow_count <= 0;
            frame_nonzero_samples <= 0;
            last_nonzero_samples <= 0;
            sync_error_sticky <= 0;
            underflow_sticky <= 0;
            box_enable_frame <= 1'b0;
            box_x0_frame <= 0;
            box_x1_frame <= 0;
            box_y0_frame <= 0;
            box_y1_frame <= 0;
            result_valid_frame <= 1'b0;
            result_class_frame <= 1'b0;
            result_valid_meta <= 1'b0;
            result_valid_sync <= 1'b0;
            result_class_meta <= 1'b0;
            result_class_sync <= 1'b0;
            result_invalid_meta <= 1'b0;
            result_invalid_sync <= 1'b0;
            result_invalid_frame <= 1'b0;
            pixel_data <= 0;
            data_enable <= 0;
            hsync_n <= 1;
            vsync_n <= 1;
        end else begin
            // Python result bits originate in the 100 MHz AXI GPIO domain.
            // Synchronize them before sampling once per incoming video frame.
            result_valid_meta <= result_valid;
            result_valid_sync <= result_valid_meta;
            result_class_meta <= result_class;
            result_class_sync <= result_class_meta;
            result_invalid_meta <= result_invalid;
            result_invalid_sync <= result_invalid_meta;
            if (x == H_TOTAL - 1) begin
                x <= 0;
                y <= (y == V_TOTAL - 1) ? 0 : y + 1'b1;
            end else begin
                x <= x + 1'b1;
            end
            data_enable <= (x < H_ACTIVE) && (y < V_ACTIVE);
            hsync_n <= !((x >= H_SYNC_START) && (x < H_SYNC_END));
            vsync_n <= !((y >= V_SYNC_START) && (y < V_SYNC_END));
            pixel_data <= 24'd0;

            case (state)
                SEARCH: if (s_axis_tvalid && s_axis_tuser) begin
                    pending_pixel <= s_axis_tdata;
                    frame_nonzero_samples <= 0;
                    box_enable_frame <= box_enable;
                    box_x0_frame <= box_x0;
                    box_x1_frame <= box_x1;
                    box_y0_frame <= box_y0;
                    box_y1_frame <= box_y1;
                    result_valid_frame <= result_valid_sync;
                    result_class_frame <= result_class_sync;
                    result_invalid_frame <= result_invalid_sync;
                    state <= WAIT_FRAME;
                end
                WAIT_FRAME: if (first_image) begin
                    pixel_data <= rgb565_to_rgb(pending_pixel);
                    state <= ACTIVE;
                end
                ACTIVE: if (in_image) begin
                    if (!s_axis_tvalid) begin
                        underflow_sticky <= 1'b1;
                        underflow_count <= underflow_count + 1'b1;
                        state <= SEARCH;
                    end else if (s_axis_tuser || (s_axis_tlast != last_column)) begin
                        sync_error_sticky <= 1'b1;
                        if (s_axis_tuser) begin
                            pending_pixel <= s_axis_tdata;
                            box_enable_frame <= box_enable;
                            box_x0_frame <= box_x0;
                            box_x1_frame <= box_x1;
                            box_y0_frame <= box_y0;
                            box_y1_frame <= box_y1;
                            result_valid_frame <= result_valid_sync;
                            result_class_frame <= result_class_sync;
                            result_invalid_frame <= result_invalid_sync;
                            state <= WAIT_FRAME;
                        end else begin
                            state <= SEARCH;
                        end
                    end else begin
                        if (draw_box)
                            pixel_data <= 24'hff0000;
                        else if (COMPARE_MODE && !SIX_PANEL_MODE &&
                                 ((x == 11'd639) || (x == 11'd640)))
                            pixel_data <= 24'hffffff;
                        else
                            pixel_data <= rgb565_to_rgb(s_axis_tdata);
                        if ((image_x[3:0] == 0) && (image_y[3:0] == 0) &&
                            (s_axis_tdata != 16'd0) &&
                            (frame_nonzero_samples != 16'hffff))
                            frame_nonzero_samples <= frame_nonzero_samples + 1'b1;
                        if (last_image) begin
                            displayed_frames <= displayed_frames + 1'b1;
                            last_nonzero_samples <= frame_nonzero_samples;
                            state <= SEARCH;
                        end
                    end
                end
                default: state <= SEARCH;
            endcase
            if (in_result_panel)
                pixel_data <= draw_label ? 24'hffffff : 24'h101820;
            if (in_compare_banner)
                pixel_data <= draw_compare_label ? 24'hffffff : 24'h101820;
            if (title_area)
                pixel_data <= draw_title ? 24'hffffff : 24'h101820;
        end
    end
endmodule
