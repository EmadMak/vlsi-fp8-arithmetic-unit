// fp8_addsub.v
// FP8 E4M3 Addition and Subtraction Unit
// Does not use +, -, * operators - uses gate-level arithmetic

`include "fp8_pkg.vh"

module fp8_addsub (
    input  wire        clk,
    input  wire        reset_n,
    input  wire        start,
    input  wire [7:0]  a_fp8,
    input  wire [7:0]  b_fp8,
    input  wire        is_sub,      // 0=add, 1=subtract
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
    localparam ALIGN     = 3'd2;
    localparam COMPUTE   = 3'd3;  // Apply alignment shift
    localparam COMPUTE2  = 3'd4;  // Perform add/sub on aligned mantissas
    localparam NORMALIZE = 3'd5;
    localparam PACK      = 3'd6;

    reg [2:0] state, next_state;

    // Unpacked fields
    reg        sign_a, sign_b, sign_result;
    reg [3:0]  exp_a, exp_b, exp_result;
    reg [3:0]  exp_diff;
    reg [7:0]  mant_a, mant_b;      // {hidden, mantissa[2:0], guard, round, sticky, 0}
    reg [7:0]  mant_a_aligned, mant_b_aligned;  // After alignment
    reg [8:0]  mant_result;         // Extra bit for overflow
    reg        a_is_zero, b_is_zero;
    reg        a_larger;             // |A| >= |B| (by exponent)
    reg        a_mag_larger;         // |A| >= |B| (by full magnitude)
    reg        eff_sub;              // Effective subtraction
    reg [3:0]  shift_amt;
    reg        guard_bit, round_bit;

    // Wires for gate-level arithmetic
    wire [3:0] exp_diff_ab, exp_diff_ba;
    wire       exp_a_ge_b;
    wire [7:0] mant_shifted_b, mant_shifted_a;
    wire       sticky_bit_b, sticky_bit_a;
    wire [8:0] mant_sum;
    wire       mant_aligned_a_ge_b;
    wire [4:0] exp_inc, exp_dec;
    wire [3:0] lzc_out;
    wire [4:0] exp_adjusted;

    // Gate-level 4-bit subtractor for exponent difference
    wire [3:0] exp_b_neg;
    wire [3:0] exp_a_neg;

    // Two's complement of exp_b
    assign exp_b_neg = ~exp_b;

    // Two's complement of exp_a
    assign exp_a_neg = ~exp_a;

    // exp_a - exp_b using adder with two's complement
    wire [3:0] exp_diff_ab_internal;
    wire       carry_exp_ab;
    adder_4bit u_exp_diff_ab (
        .a(exp_a),
        .b(exp_b_neg),
        .cin(1'b1),
        .sum(exp_diff_ab_internal),
        .cout(carry_exp_ab)
    );
    assign exp_diff_ab = exp_diff_ab_internal;
    assign exp_a_ge_b = carry_exp_ab;  // No borrow means A >= B

    // exp_b - exp_a using adder with two's complement
    wire [3:0] exp_diff_ba_internal;
    wire       carry_exp_ba;
    adder_4bit u_exp_diff_ba (
        .a(exp_b),
        .b(exp_a_neg),
        .cin(1'b1),
        .sum(exp_diff_ba_internal),
        .cout(carry_exp_ba)
    );
    assign exp_diff_ba = exp_diff_ba_internal;

    // Two barrel shifters - one for each operand
    barrel_shifter_right_8 u_shifter_b (
        .in(mant_b),
        .shift(shift_amt),
        .out(mant_shifted_b),
        .sticky(sticky_bit_b)
    );

    barrel_shifter_right_8 u_shifter_a (
        .in(mant_a),
        .shift(shift_amt),
        .out(mant_shifted_a),
        .sticky(sticky_bit_a)
    );

    // Mantissa comparison (8-bit) - compare ALIGNED mantissas
    wire [7:0] mant_b_aligned_neg;
    assign mant_b_aligned_neg = ~mant_b_aligned;
    wire [7:0] mant_cmp;
    wire       carry_mant_cmp;
    adder_8bit u_mant_cmp (
        .a(mant_a_aligned),
        .b(mant_b_aligned_neg),
        .cin(1'b1),
        .sum(mant_cmp),
        .cout(carry_mant_cmp)
    );
    assign mant_aligned_a_ge_b = carry_mant_cmp;

    // Mantissa addition using ALIGNED mantissas
    wire [8:0] mant_add_result;
    wire       carry_mant_add;
    adder_9bit u_mant_add (
        .a({1'b0, mant_a_aligned}),
        .b({1'b0, mant_b_aligned}),
        .cin(1'b0),
        .sum(mant_add_result),
        .cout(carry_mant_add)
    );
    assign mant_sum = mant_add_result;

    // Mantissa subtraction (a_aligned - b_aligned)
    // Two's complement: A - B = A + (~B) + 1
    // For 9-bit: {0,A} - {0,B} = {0,A} + ~{0,B} + 1 = {0,A} + {1,~B} + 1
    wire [8:0] mant_b_ext_neg;
    assign mant_b_ext_neg = {1'b1, mant_b_aligned_neg};  // Proper 9-bit two's complement
    wire [8:0] mant_sub_ab;
    wire       carry_sub_ab;
    adder_9bit u_mant_sub_ab (
        .a({1'b0, mant_a_aligned}),
        .b(mant_b_ext_neg),
        .cin(1'b1),
        .sum(mant_sub_ab),
        .cout(carry_sub_ab)
    );

    // Mantissa subtraction (b_aligned - a_aligned)
    wire [7:0] mant_a_aligned_neg;
    assign mant_a_aligned_neg = ~mant_a_aligned;
    wire [8:0] mant_a_ext_neg;
    assign mant_a_ext_neg = {1'b1, mant_a_aligned_neg};  // Proper 9-bit two's complement
    wire [8:0] mant_sub_ba;
    wire       carry_sub_ba;
    adder_9bit u_mant_sub_ba (
        .a({1'b0, mant_b_aligned}),
        .b(mant_a_ext_neg),
        .cin(1'b1),
        .sum(mant_sub_ba),
        .cout(carry_sub_ba)
    );

    // mant_sub_ab and mant_sub_ba are used directly in COMPUTE2 state

    // Exponent increment
    adder_5bit u_exp_inc (
        .a({1'b0, exp_result}),
        .b(5'd1),
        .cin(1'b0),
        .sum(exp_inc),
        .cout()
    );

    // Leading zero counter for normalization
    leading_zero_counter_8 u_lzc (
        .in(mant_result[7:0]),
        .count(lzc_out)
    );

    // Exponent decrement by LZC amount
    wire [4:0] lzc_neg;
    assign lzc_neg = ~{1'b0, lzc_out};
    adder_5bit u_exp_dec (
        .a({1'b0, exp_result}),
        .b(lzc_neg),
        .cin(1'b1),
        .sum(exp_adjusted),
        .cout()
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
            UNPACK:    next_state = ALIGN;
            ALIGN:     next_state = COMPUTE;
            COMPUTE:   next_state = COMPUTE2;
            COMPUTE2:  next_state = NORMALIZE;
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
            exp_result <= 4'd0;
            exp_diff <= 4'd0;
            mant_a <= 8'd0;
            mant_b <= 8'd0;
            mant_a_aligned <= 8'd0;
            mant_b_aligned <= 8'd0;
            mant_result <= 9'd0;
            a_is_zero <= 1'b0;
            b_is_zero <= 1'b0;
            a_larger <= 1'b0;
            a_mag_larger <= 1'b0;
            eff_sub <= 1'b0;
            shift_amt <= 4'd0;
            guard_bit <= 1'b0;
            round_bit <= 1'b0;
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
                    // Extract fields from operands
                    sign_a <= a_fp8[7];
                    sign_b <= b_fp8[7] ^ is_sub;  // Flip sign for subtraction
                    exp_a <= a_fp8[6:3];
                    exp_b <= b_fp8[6:3];

                    // Check for zeros
                    a_is_zero <= (a_fp8[6:0] == 7'd0);
                    b_is_zero <= (b_fp8[6:0] == 7'd0);

                    // Construct mantissa with hidden bit and guard bits
                    // Format: {hidden, mantissa[2:0], guard, round, sticky, 0}
                    if (a_fp8[6:3] == 4'd0) begin
                        // Denormalized: hidden bit is 0
                        mant_a <= {1'b0, a_fp8[2:0], 4'b0000};
                    end else begin
                        // Normalized: hidden bit is 1
                        mant_a <= {1'b1, a_fp8[2:0], 4'b0000};
                    end

                    if (b_fp8[6:3] == 4'd0) begin
                        mant_b <= {1'b0, b_fp8[2:0], 4'b0000};
                    end else begin
                        mant_b <= {1'b1, b_fp8[2:0], 4'b0000};
                    end

                    // Determine effective operation: subtraction if signs differ
                    // sign_b already has is_sub XORed in, so just compare sign_a with effective sign_b
                    // eff_sub = 1 means we subtract mantissas (signs differ)
                    // eff_sub = 0 means we add mantissas (signs same)
                    eff_sub <= a_fp8[7] ^ (b_fp8[7] ^ is_sub);
                end

                ALIGN: begin
                    // Handle zero operands
                    if (a_is_zero && b_is_zero) begin
                        exp_result <= 4'd0;
                        mant_result <= 9'd0;
                        sign_result <= sign_a & sign_b;
                        mant_a_aligned <= 8'd0;
                        mant_b_aligned <= 8'd0;
                    end else if (a_is_zero) begin
                        exp_result <= exp_b;
                        mant_result <= {1'b0, mant_b};
                        sign_result <= sign_b;
                        mant_a_aligned <= 8'd0;
                        mant_b_aligned <= mant_b;
                    end else if (b_is_zero) begin
                        exp_result <= exp_a;
                        mant_result <= {1'b0, mant_a};
                        sign_result <= sign_a;
                        mant_a_aligned <= mant_a;
                        mant_b_aligned <= 8'd0;
                    end else begin
                        // Align mantissas to larger exponent
                        if (exp_a_ge_b) begin
                            exp_result <= exp_a;
                            shift_amt <= exp_diff_ab;
                            a_larger <= 1'b1;
                            // A has larger/equal exponent, shift B
                            mant_a_aligned <= mant_a;
                            // mant_b_aligned will use mant_shifted_b in COMPUTE
                        end else begin
                            exp_result <= exp_b;
                            shift_amt <= exp_diff_ba;
                            a_larger <= 1'b0;
                            // B has larger exponent, shift A
                            mant_b_aligned <= mant_b;
                            // mant_a_aligned will use mant_shifted_a in COMPUTE
                        end
                    end
                end

                COMPUTE: begin
                    if (a_is_zero || b_is_zero) begin
                        // Already handled in ALIGN
                    end else begin
                        // Apply shift to smaller operand's mantissa
                        if (a_larger) begin
                            // A has larger exponent, B was shifted
                            mant_b_aligned <= mant_shifted_b;
                            // mant_a_aligned already set in ALIGN
                        end else begin
                            // B has larger exponent, A was shifted
                            mant_a_aligned <= mant_shifted_a;
                            // mant_b_aligned already set in ALIGN
                        end
                    end
                end

                COMPUTE2: begin
                    if (a_is_zero || b_is_zero) begin
                        // Already handled in ALIGN
                    end else begin
                        // Now aligned mantissas are ready - determine magnitude and compute
                        // Use the comparator result for aligned mantissas
                        a_mag_larger <= mant_aligned_a_ge_b;

                        // Debug output
                        $display("COMPUTE2: eff_sub=%b, sign_a=%b, sign_b=%b", eff_sub, sign_a, sign_b);
                        $display("  mant_a_aligned=%h, mant_b_aligned=%h", mant_a_aligned, mant_b_aligned);
                        $display("  mant_sum=%h, mant_sub_ab=%h, mant_sub_ba=%h", mant_sum, mant_sub_ab, mant_sub_ba);

                        // Perform addition or subtraction
                        if (eff_sub == 1'b0) begin
                            // Effective addition: same signs
                            mant_result <= mant_sum;
                            sign_result <= sign_a;
                        end else begin
                            // Effective subtraction: different signs
                            // Result sign depends on which operand has larger magnitude
                            if (mant_aligned_a_ge_b) begin
                                // |A| >= |B|, use A - B, sign = sign_a
                                mant_result <= mant_sub_ab;
                                sign_result <= sign_a;
                            end else begin
                                // |B| > |A|, use B - A, sign = sign_b
                                mant_result <= mant_sub_ba;
                                sign_result <= sign_b;
                            end
                        end
                    end
                end

                NORMALIZE: begin
                    if (mant_result == 9'd0) begin
                        // Result is zero
                        exp_result <= 4'd0;
                        flag_zero <= 1'b1;
                        sign_result <= 1'b0;  // +0
                    end else if (mant_result[8]) begin
                        // Overflow in mantissa, shift right
                        mant_result <= mant_result >> 1;
                        guard_bit <= mant_result[0];
                        if (exp_inc[4]) begin
                            // Exponent overflow
                            flag_overflow <= 1'b1;
                            exp_result <= 4'b1110;  // Max exponent
                            mant_result <= 9'b0_0111_0000;  // Max mantissa
                        end else begin
                            exp_result <= exp_inc[3:0];
                        end
                    end else if (~mant_result[7] && exp_result != 4'd0) begin
                        // Need to normalize left
                        if (lzc_out >= exp_result) begin
                            // Would underflow - create denormalized or zero
                            if (exp_result > 4'd1) begin
                                mant_result <= mant_result << (exp_result[2:0]);
                                exp_result <= 4'd0;
                                flag_underflow <= 1'b1;
                            end else begin
                                exp_result <= 4'd0;
                                flag_underflow <= 1'b1;
                            end
                        end else begin
                            mant_result <= mant_result << lzc_out;
                            if (exp_adjusted[4]) begin
                                exp_result <= 4'd0;
                                flag_underflow <= 1'b1;
                            end else begin
                                exp_result <= exp_adjusted[3:0];
                            end
                        end
                    end

                    // Rounding (round to nearest even)
                    if (mant_result[3:0] != 4'd0) begin
                        flag_inexact <= 1'b1;
                    end
                end

                PACK: begin
                    // Round and pack result
                    if (flag_overflow) begin
                        result_fp8 <= {sign_result, 4'b1110, 3'b111};
                    end else if (flag_zero || (exp_result == 4'd0 && mant_result[7:4] == 4'd0)) begin
                        result_fp8 <= {sign_result, 7'd0};
                        flag_zero <= 1'b1;
                    end else begin
                        // Apply rounding
                        if (mant_result[3] && (mant_result[4] || mant_result[2:0] != 3'd0)) begin
                            // Round up
                            if (mant_result[6:4] == 3'b111) begin
                                // Mantissa overflow from rounding
                                if (exp_result == 4'b1110) begin
                                    flag_overflow <= 1'b1;
                                    result_fp8 <= {sign_result, 4'b1110, 3'b111};
                                end else begin
                                    result_fp8 <= {sign_result, exp_inc[3:0], 3'b000};
                                end
                            end else begin
                                result_fp8 <= {sign_result, exp_result, mant_result[6:4]};
                            end
                            flag_inexact <= 1'b1;
                        end else begin
                            result_fp8 <= {sign_result, exp_result, mant_result[6:4]};
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

// Gate-level Full Adder
module full_adder (
    input  wire a,
    input  wire b,
    input  wire cin,
    output wire sum,
    output wire cout
);
    wire ab_xor, ab_and, cin_and;

    assign ab_xor = a ^ b;
    assign sum = ab_xor ^ cin;
    assign ab_and = a & b;
    assign cin_and = ab_xor & cin;
    assign cout = ab_and | cin_and;
endmodule

// 4-bit Ripple Carry Adder
module adder_4bit (
    input  wire [3:0] a,
    input  wire [3:0] b,
    input  wire       cin,
    output wire [3:0] sum,
    output wire       cout
);
    wire [3:0] c;

    full_adder fa0 (.a(a[0]), .b(b[0]), .cin(cin),  .sum(sum[0]), .cout(c[0]));
    full_adder fa1 (.a(a[1]), .b(b[1]), .cin(c[0]), .sum(sum[1]), .cout(c[1]));
    full_adder fa2 (.a(a[2]), .b(b[2]), .cin(c[1]), .sum(sum[2]), .cout(c[2]));
    full_adder fa3 (.a(a[3]), .b(b[3]), .cin(c[2]), .sum(sum[3]), .cout(cout));
endmodule

// 5-bit Ripple Carry Adder
module adder_5bit (
    input  wire [4:0] a,
    input  wire [4:0] b,
    input  wire       cin,
    output wire [4:0] sum,
    output wire       cout
);
    wire [4:0] c;

    full_adder fa0 (.a(a[0]), .b(b[0]), .cin(cin),  .sum(sum[0]), .cout(c[0]));
    full_adder fa1 (.a(a[1]), .b(b[1]), .cin(c[0]), .sum(sum[1]), .cout(c[1]));
    full_adder fa2 (.a(a[2]), .b(b[2]), .cin(c[1]), .sum(sum[2]), .cout(c[2]));
    full_adder fa3 (.a(a[3]), .b(b[3]), .cin(c[2]), .sum(sum[3]), .cout(c[3]));
    full_adder fa4 (.a(a[4]), .b(b[4]), .cin(c[3]), .sum(sum[4]), .cout(cout));
endmodule

// 8-bit Ripple Carry Adder
module adder_8bit (
    input  wire [7:0] a,
    input  wire [7:0] b,
    input  wire       cin,
    output wire [7:0] sum,
    output wire       cout
);
    wire c4;

    adder_4bit lo (.a(a[3:0]), .b(b[3:0]), .cin(cin), .sum(sum[3:0]), .cout(c4));
    adder_4bit hi (.a(a[7:4]), .b(b[7:4]), .cin(c4),  .sum(sum[7:4]), .cout(cout));
endmodule

// 9-bit Ripple Carry Adder
module adder_9bit (
    input  wire [8:0] a,
    input  wire [8:0] b,
    input  wire       cin,
    output wire [8:0] sum,
    output wire       cout
);
    wire c8;

    adder_8bit lo (.a(a[7:0]), .b(b[7:0]), .cin(cin), .sum(sum[7:0]), .cout(c8));
    full_adder  hi (.a(a[8]),   .b(b[8]),   .cin(c8),  .sum(sum[8]),   .cout(cout));
endmodule

// Leading Zero Counter (8-bit input)
module leading_zero_counter_8 (
    input  wire [7:0] in,
    output reg  [3:0] count
);
    always @(*) begin
        casez (in)
            8'b1???????: count = 4'd0;
            8'b01??????: count = 4'd1;
            8'b001?????: count = 4'd2;
            8'b0001????: count = 4'd3;
            8'b00001???: count = 4'd4;
            8'b000001??: count = 4'd5;
            8'b0000001?: count = 4'd6;
            8'b00000001: count = 4'd7;
            8'b00000000: count = 4'd8;
            default:     count = 4'd0;
        endcase
    end
endmodule

// Barrel Shifter Right (8-bit)
module barrel_shifter_right_8 (
    input  wire [7:0] in,
    input  wire [3:0] shift,
    output wire [7:0] out,
    output wire       sticky
);
    wire [7:0] stage0, stage1, stage2, stage3;
    wire [7:0] shifted_out0, shifted_out1, shifted_out2, shifted_out3;

    // Stage 0: shift by 0 or 1
    assign stage0 = shift[0] ? {1'b0, in[7:1]} : in;
    assign shifted_out0 = shift[0] ? {7'b0, in[0]} : 8'b0;

    // Stage 1: shift by 0 or 2
    assign stage1 = shift[1] ? {2'b0, stage0[7:2]} : stage0;
    assign shifted_out1 = shift[1] ? {6'b0, stage0[1:0]} | shifted_out0 : shifted_out0;

    // Stage 2: shift by 0 or 4
    assign stage2 = shift[2] ? {4'b0, stage1[7:4]} : stage1;
    assign shifted_out2 = shift[2] ? {4'b0, stage1[3:0]} | shifted_out1 : shifted_out1;

    // Stage 3: shift by 0 or 8
    assign stage3 = shift[3] ? 8'b0 : stage2;
    assign shifted_out3 = shift[3] ? stage2 | shifted_out2 : shifted_out2;

    assign out = stage3;
    assign sticky = |shifted_out3;  // OR of all shifted-out bits
endmodule
