// fp8_top.v
// Top-level integration for FP8 arithmetic unit
// FP8 format: [7] sign | [6:3] exponent (bias=7) | [2:0] mantissa

`include "fp8_pkg.vh"

module fp8_top (
    // Clock and reset
    input  wire       clk,
    input  wire       reset_n,     // Active-low reset

    // Control signals
    input  wire       start,       // Start operation (pulse or level)
    output reg        done,        // Operation complete

    // Input operands
    input  wire [7:0] a_fp8,       // Operand A (FP8 format)
    input  wire [7:0] b_fp8,       // Operand B (FP8 format)
    input  wire [1:0] op,          // Operation: 00=add, 01=sub, 10=mul, 11=reserved

    // Output result
    output reg  [7:0] result_fp8,  // Result in FP8 format

    // Status flags
    output reg        flag_zero,     // Result is zero
    output reg        flag_overflow, // Exponent overflow (result clamped)
    output reg        flag_underflow,// Exponent underflow (denorm or flush-to-zero)
    output reg        flag_inexact   // Rounding occurred
);

    // Internal signals for add/sub unit
    wire        addsub_done;
    wire [7:0]  addsub_result;
    wire        addsub_zero;
    wire        addsub_overflow;
    wire        addsub_underflow;
    wire        addsub_inexact;
    wire        is_sub;

    // Internal signals for multiply unit
    wire        mult_done;
    wire [7:0]  mult_result;
    wire        mult_zero;
    wire        mult_overflow;
    wire        mult_underflow;
    wire        mult_inexact;

    // Operation decode
    wire        op_is_add;
    wire        op_is_sub;
    wire        op_is_mul;
    wire        op_is_addsub;

    assign op_is_add = (op == `OP_ADD);
    assign op_is_sub = (op == `OP_SUB);
    assign op_is_mul = (op == `OP_MUL);
    assign op_is_addsub = op_is_add | op_is_sub;
    assign is_sub = op_is_sub;

    // Start signals for sub-units
    wire start_addsub;
    wire start_mult;

    assign start_addsub = start & op_is_addsub;
    assign start_mult   = start & op_is_mul;

    // Instantiate add/sub unit
    fp8_addsub u_addsub (
        .clk            (clk),
        .reset_n        (reset_n),
        .start          (start_addsub),
        .a_fp8          (a_fp8),
        .b_fp8          (b_fp8),
        .is_sub         (is_sub),
        .done           (addsub_done),
        .result_fp8     (addsub_result),
        .flag_zero      (addsub_zero),
        .flag_overflow  (addsub_overflow),
        .flag_underflow (addsub_underflow),
        .flag_inexact   (addsub_inexact)
    );

    // Instantiate multiply unit
    fp8_mult u_mult (
        .clk            (clk),
        .reset_n        (reset_n),
        .start          (start_mult),
        .a_fp8          (a_fp8),
        .b_fp8          (b_fp8),
        .done           (mult_done),
        .result_fp8     (mult_result),
        .flag_zero      (mult_zero),
        .flag_overflow  (mult_overflow),
        .flag_underflow (mult_underflow),
        .flag_inexact   (mult_inexact)
    );

    // Latched operation for output mux
    reg [1:0] op_latched;

    always @(posedge clk or negedge reset_n) begin
        if (~reset_n) begin
            op_latched <= 2'b00;
        end else if (start) begin
            op_latched <= op;
        end
    end

    // Output multiplexing
    always @(posedge clk or negedge reset_n) begin
        if (~reset_n) begin
            done <= 1'b0;
            result_fp8 <= 8'd0;
            flag_zero <= 1'b0;
            flag_overflow <= 1'b0;
            flag_underflow <= 1'b0;
            flag_inexact <= 1'b0;
        end else begin
            // Default: clear done
            done <= 1'b0;

            // Select output based on operation
            case (op_latched)
                `OP_ADD, `OP_SUB: begin
                    if (addsub_done) begin
                        done <= 1'b1;
                        result_fp8 <= addsub_result;
                        flag_zero <= addsub_zero;
                        flag_overflow <= addsub_overflow;
                        flag_underflow <= addsub_underflow;
                        flag_inexact <= addsub_inexact;
                    end
                end

                `OP_MUL: begin
                    if (mult_done) begin
                        done <= 1'b1;
                        result_fp8 <= mult_result;
                        flag_zero <= mult_zero;
                        flag_overflow <= mult_overflow;
                        flag_underflow <= mult_underflow;
                        flag_inexact <= mult_inexact;
                    end
                end

                `OP_RESERVED: begin
                    // Reserved operation - return zero with done
                    if (start) begin
                        done <= 1'b1;
                        result_fp8 <= 8'd0;
                        flag_zero <= 1'b1;
                        flag_overflow <= 1'b0;
                        flag_underflow <= 1'b0;
                        flag_inexact <= 1'b0;
                    end
                end

                default: begin
                    done <= 1'b0;
                end
            endcase
        end
    end

endmodule
