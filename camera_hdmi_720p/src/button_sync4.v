`timescale 1ns / 1ps

// Two-flop synchronizer for the four asynchronous PYNQ-Z1 push buttons.
module button_sync4 (
    input  wire       clk,
    input  wire       resetn,
    input  wire [3:0] buttons_async,
    output wire [3:0] buttons_sync
);
    (* ASYNC_REG = "TRUE" *) reg [3:0] meta;
    (* ASYNC_REG = "TRUE" *) reg [3:0] sync;

    always @(posedge clk) begin
        if (!resetn) begin
            meta <= 4'b0000;
            sync <= 4'b0000;
        end else begin
            meta <= buttons_async;
            sync <= meta;
        end
    end

    assign buttons_sync = sync;
endmodule
