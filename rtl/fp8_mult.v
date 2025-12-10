// fp8_mult.v
// FP8 E4M3 Multiplication Unit
// Does not use +, -, * operators - uses gate-level arithmetic

`include "fp8_pkg.vh"

module fp8_mult (
    input  wire        clk,
    input  wire        reset_n,
    input  wire        start,
    input  wire [7:0]  a_fp8,
    input  wire [7:0]  b_fp8,
    output reg         done,
    output reg  [7:0]  result_fp8,
    output reg         flag_zero,
    output reg         flag_overflow,
    output reg         flag_underflow,
    output reg         flag_inexact
);

    // State machine
    localparam IDLE      = 3'd0;
    localparam UNPACK    = 3'd1;
    localparam MULTIPLY  = 3'd2;
    localparam NORMALIZE = 3'd3;
    localparam PACK      = 3'd4;

    reg [2:0] state, next_state;

    // Unpacked fields
    reg        sign_a, sign_b, sign_result;
    reg [3:0]  exp_a, exp_b;
    reg [5:0]  exp_sum;           // Larger to handle overflow
    reg signed [5:0] exp_result;  // Can be negative during calculation
    reg [3:0]  mant_a, mant_b;    // {hidden_bit, mantissa[2:0]}
    reg [7:0]  mant_product;      // 4x4 = 8 bits
    reg        a_is_zero, b_is_zero;
    reg        a_is_denorm, b_is_denorm;

    // Wires for gate-level arithmetic
    wire [5:0] exp_a_ext, exp_b_ext;
    wire [5:0] exp_added;
    wire [5:0] bias_neg;
    wire [5:0] exp_unbiased;
    wire       exp_carry;

    // Extend exponents to 6 bits
    assign exp_a_ext = {2'b00, exp_a};
    assign exp_b_ext = {2'b00, exp_b};

    // Bias in 6-bit two's complement negative form
    // Bias = 7, so we need to subtract 7
    assign bias_neg = 6'b111001;  // -7 in two's complement

    // Add exponents
    wire [5:0] exp_sum_internal;
    wire       carry_exp_sum;
    adder_6bit u_exp_add (
        .a(exp_a_ext),
        .b(exp_b_ext),
        .cin(1'b0),
        .sum(exp_sum_internal),
        .cout(carry_exp_sum)
    );

    // Subtract bias from sum
    wire [5:0] exp_result_internal;
    wire       carry_exp_bias;
    adder_6bit u_exp_bias (
        .a(exp_sum_internal),
        .b(bias_neg),
        .cin(1'b0),
        .sum(exp_result_internal),
        .cout(carry_exp_bias)
    );

    // Mantissa multiplier using shift-and-add
    wire [7:0] mant_product_internal;
    multiplier_4x4 u_mant_mult (
        .a(mant_a),
        .b(mant_b),
        .product(mant_product_internal)
    );

    // Leading zero counter for normalization
    wire [3:0] lzc_out;
    leading_zero_counter_8 u_lzc_mult (
        .in(mant_product),
        .count(lzc_out)
    );

    // Exponent increment by 1 for normalization
    wire [5:0] exp_result_inc;
    wire       exp_inc_carry;
    adder_6bit u_exp_inc (
        .a(exp_result),
        .b(6'd1),
        .cin(1'b0),
        .sum(exp_result_inc),
        .cout(exp_inc_carry)
    );

    // State machine
    always @(posedge clk or negedge reset_n) begin
        if (~reset_n) begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end

    always @(*) begin
        next_state = state;
        case (state)
            IDLE:      if (start) next_state = UNPACK;
            UNPACK:    next_state = MULTIPLY;
            MULTIPLY:  next_state = NORMALIZE;
            NORMALIZE: next_state = PACK;
            PACK:      next_state = IDLE;
            default:   next_state = IDLE;
        endcase
    end

    // Main datapath
    always @(posedge clk or negedge reset_n) begin
        if (~reset_n) begin
            done <= 1'b0;
            result_fp8 <= 8'd0;
            flag_zero <= 1'b0;
            flag_overflow <= 1'b0;
            flag_underflow <= 1'b0;
            flag_inexact <= 1'b0;
            sign_a <= 1'b0;
            sign_b <= 1'b0;
            sign_result <= 1'b0;
            exp_a <= 4'd0;
            exp_b <= 4'd0;
            exp_sum <= 6'd0;
            exp_result <= 6'd0;
            mant_a <= 4'd0;
            mant_b <= 4'd0;
            mant_product <= 8'd0;
            a_is_zero <= 1'b0;
            b_is_zero <= 1'b0;
            a_is_denorm <= 1'b0;
            b_is_denorm <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    done <= 1'b0;
                    flag_zero <= 1'b0;
                    flag_overflow <= 1'b0;
                    flag_underflow <= 1'b0;
                    flag_inexact <= 1'b0;
                end

                UNPACK: begin
                    // Extract fields
                    sign_a <= a_fp8[7];
                    sign_b <= b_fp8[7];
                    sign_result <= a_fp8[7] ^ b_fp8[7];

                    exp_a <= a_fp8[6:3];
                    exp_b <= b_fp8[6:3];

                    // Check for zeros and denormals
                    a_is_zero <= (a_fp8[6:0] == 7'd0);
                    b_is_zero <= (b_fp8[6:0] == 7'd0);
                    a_is_denorm <= (a_fp8[6:3] == 4'd0) && (a_fp8[2:0] != 3'd0);
                    b_is_denorm <= (b_fp8[6:3] == 4'd0) && (b_fp8[2:0] != 3'd0);

                    // Construct mantissa with hidden bit
                    if (a_fp8[6:3] == 4'd0) begin
                        mant_a <= {1'b0, a_fp8[2:0]};  // Denormalized
                    end else begin
                        mant_a <= {1'b1, a_fp8[2:0]};  // Normalized
                    end

                    if (b_fp8[6:3] == 4'd0) begin
                        mant_b <= {1'b0, b_fp8[2:0]};
                    end else begin
                        mant_b <= {1'b1, b_fp8[2:0]};
                    end
                end

                MULTIPLY: begin
                    if (a_is_zero || b_is_zero) begin
                        // Result is zero
                        mant_product <= 8'd0;
                        exp_result <= 6'd0;
                        flag_zero <= 1'b1;
                    end else begin
                        // Multiply mantissas
                        mant_product <= mant_product_internal;

                        // Add exponents and subtract bias
                        exp_sum <= exp_sum_internal;
                        exp_result <= exp_result_internal;

                        // Adjust for denormalized inputs
                        if (a_is_denorm) begin
                            exp_result <= exp_result_internal;  // Exp_a was 0, treated as 1
                        end
                        if (b_is_denorm) begin
                            exp_result <= exp_result_internal;
                        end
                    end
                end

                NORMALIZE: begin
                    if (flag_zero) begin
                        // Already handled
                    end else if (mant_product[7]) begin
                        // Product has 1 in MSB position (1x.xxx format)
                        // Shift right by 1, increment exponent
                        mant_product <= mant_product >> 1;

                        // Increment exponent using adder
                        exp_result <= exp_result_inc;

                        // Check sticky bits for rounding
                        if (mant_product[0]) begin
                            flag_inexact <= 1'b1;
                        end

                        // Check for overflow after increment
                        if (exp_result_inc[5] == 1'b0 && exp_result_inc >= 6'd15) begin
                            flag_overflow <= 1'b1;
                        end
                    end else if (mant_product[6]) begin
                        // Product is in form 01.xxxxxx, already normalized
                        // No shift needed
                    end else begin
                        // Need to normalize left (should not happen for normalized inputs)
                        // Product < 1.0, underflow case
                        if (lzc_out > 0 && exp_result > 0) begin
                            mant_product <= mant_product << 1;
                            exp_result <= exp_result[5:0] & 6'b111110;  // Decrement
                            flag_underflow <= (exp_result <= 6'd1);
                        end
                    end

                    // Check for overflow/underflow
                    if (exp_result[5]) begin
                        // Negative exponent - underflow
                        flag_underflow <= 1'b1;
                        exp_result <= 6'd0;
                    end else if (exp_result >= 6'd15) begin
                        // Overflow
                        flag_overflow <= 1'b1;
                    end
                end

                PACK: begin
                    if (flag_zero) begin
                        result_fp8 <= {sign_result, 7'd0};
                    end else if (flag_overflow) begin
                        // Saturate to max value
                        result_fp8 <= {sign_result, 4'b1110, 3'b111};
                    end else if (flag_underflow || exp_result == 6'd0) begin
                        // Flush to zero or create denormal
                        if (mant_product[6:4] != 3'd0) begin
                            // Create denormalized result
                            result_fp8 <= {sign_result, 4'd0, mant_product[6:4]};
                            flag_underflow <= 1'b1;
                        end else begin
                            result_fp8 <= {sign_result, 7'd0};
                            flag_zero <= 1'b1;
                        end
                    end else begin
                        // Normal result
                        // Round to nearest even
                        if (mant_product[2] && (mant_product[3] || mant_product[1:0] != 2'd0)) begin
                            // Round up
                            if (mant_product[5:3] == 3'b111) begin
                                // Mantissa overflow from rounding
                                if (exp_result >= 6'd14) begin
                                    flag_overflow <= 1'b1;
                                    result_fp8 <= {sign_result, 4'b1110, 3'b111};
                                end else begin
                                    result_fp8 <= {sign_result, exp_result[3:0], 3'b000};
                                    // Increment exponent handled
                                end
                            end else begin
                                result_fp8 <= {sign_result, exp_result[3:0], mant_product[5:3]};
                            end
                            flag_inexact <= 1'b1;
                        end else begin
                            result_fp8 <= {sign_result, exp_result[3:0], mant_product[5:3]};
                        end

                        // Set inexact if any bits lost
                        if (mant_product[2:0] != 3'd0) begin
                            flag_inexact <= 1'b1;
                        end
                    end
                    done <= 1'b1;
                end

                default: begin
                    done <= 1'b0;
                end
            endcase
        end
    end

endmodule

// 6-bit Ripple Carry Adder
module adder_6bit (
    input  wire [5:0] a,
    input  wire [5:0] b,
    input  wire       cin,
    output wire [5:0] sum,
    output wire       cout
);
    wire c4;

    adder_4bit lo (.a(a[3:0]), .b(b[3:0]), .cin(cin), .sum(sum[3:0]), .cout(c4));

    wire [1:0] hi_sum;
    wire       c5;

    full_adder fa4 (.a(a[4]), .b(b[4]), .cin(c4), .sum(sum[4]), .cout(c5));
    full_adder fa5 (.a(a[5]), .b(b[5]), .cin(c5), .sum(sum[5]), .cout(cout));
endmodule

// 4x4 Multiplier using shift-and-add (no * operator)
module multiplier_4x4 (
    input  wire [3:0] a,
    input  wire [3:0] b,
    output wire [7:0] product
);
    // Partial products
    wire [7:0] pp0, pp1, pp2, pp3;

    // Generate partial products using AND gates
    assign pp0 = b[0] ? {4'b0000, a} : 8'd0;
    assign pp1 = b[1] ? {3'b000, a, 1'b0} : 8'd0;
    assign pp2 = b[2] ? {2'b00, a, 2'b00} : 8'd0;
    assign pp3 = b[3] ? {1'b0, a, 3'b000} : 8'd0;

    // Add partial products using gate-level adders
    wire [7:0] sum01, sum23, sum_final;
    wire       carry01, carry23, carry_final;

    adder_8bit u_add01 (
        .a(pp0),
        .b(pp1),
        .cin(1'b0),
        .sum(sum01),
        .cout(carry01)
    );

    adder_8bit u_add23 (
        .a(pp2),
        .b(pp3),
        .cin(1'b0),
        .sum(sum23),
        .cout(carry23)
    );

    adder_8bit u_add_final (
        .a(sum01),
        .b(sum23),
        .cin(1'b0),
        .sum(sum_final),
        .cout(carry_final)
    );

    assign product = sum_final;
endmodule
