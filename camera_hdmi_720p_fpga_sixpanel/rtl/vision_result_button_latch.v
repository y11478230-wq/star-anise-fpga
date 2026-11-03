`timescale 1ns / 1ps
// BTN0 toggles between waiting and showing a latched recognition result.
// class input encoding: 0=八角, 1=莽草, 2=未识别.
module vision_result_button_latch #(
    parameter integer CLK_HZ = 100_000_000,
    parameter integer DEBOUNCE_MS = 20
)(
    input  wire       clk,
    input  wire       resetn,
    input  wire       button,         // PYNQ-Z1 BTN0 is active high
    input  wire       result_valid,   // Belongs to the most recently completed frame
    input  wire [1:0] result_class,
    output reg        show_result,
    output reg        latched_valid,
    output reg  [1:0] latched_class
);
    localparam integer DEBOUNCE_COUNT = (CLK_HZ / 1000) * DEBOUNCE_MS;
    localparam integer COUNT_WIDTH = (DEBOUNCE_COUNT < 2) ? 1 : $clog2(DEBOUNCE_COUNT + 1);

    reg button_meta;
    reg button_sync;
    reg button_stable;
    reg [COUNT_WIDTH-1:0] debounce_count;
    reg button_stable_d;
    wire press_event = !button_stable_d && button_stable;

    always @(posedge clk) begin
        if (!resetn) begin
            button_meta      <= 1'b0;
            button_sync      <= 1'b0;
            button_stable    <= 1'b0;
            button_stable_d  <= 1'b0;
            debounce_count  <= {COUNT_WIDTH{1'b0}};
            show_result      <= 1'b0;
            latched_valid   <= 1'b0;
            latched_class    <= 2'd2;
        end else begin
            button_meta     <= button;
            button_sync     <= button_meta;
            button_stable_d <= button_stable;

            if (button_sync == button_stable) begin
                debounce_count <= {COUNT_WIDTH{1'b0}};
            end else if (debounce_count >= DEBOUNCE_COUNT - 1) begin
                debounce_count <= {COUNT_WIDTH{1'b0}};
                button_stable <= button_sync;
            end else begin
                debounce_count <= debounce_count + 1'b1;
            end

            if (press_event) begin
                if (!show_result) begin
                    show_result   <= 1'b1;
                    latched_valid <= 1'b1;
                    latched_class <= result_valid ? result_class : 2'd2;
                end else begin
                    show_result <= 1'b0;
                    latched_valid <= 1'b0;
                end
            end
        end
    end
endmodule
