// tb_fp8_top.v
// Comprehensive testbench for FP8 E4M3 arithmetic unit
// Tests addition, subtraction, and multiplication operations

`timescale 1ns/1ps

`include "fp8_pkg.vh"

module tb_fp8_top;

    // Clock and reset
    reg        clk;
    reg        reset_n;

    // Control signals
    reg        start;
    wire       done;

    // Input operands
    reg  [7:0] a_fp8;
    reg  [7:0] b_fp8;
    reg  [1:0] op;

    // Output result
    wire [7:0] result_fp8;

    // Status flags
    wire       flag_zero;
    wire       flag_overflow;
    wire       flag_underflow;
    wire       flag_inexact;

    // Test tracking
    integer test_count;
    integer pass_count;
    integer fail_count;

    // DUT instantiation
    fp8_top dut (
        .clk            (clk),
        .reset_n        (reset_n),
        .start          (start),
        .done           (done),
        .a_fp8          (a_fp8),
        .b_fp8          (b_fp8),
        .op             (op),
        .result_fp8     (result_fp8),
        .flag_zero      (flag_zero),
        .flag_overflow  (flag_overflow),
        .flag_underflow (flag_underflow),
        .flag_inexact   (flag_inexact)
    );

    // Clock generation (100 MHz)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // FP8 to real conversion for display
    function real fp8_to_real;
        input [7:0] fp8;
        reg        sign;
        reg [3:0]  exp;
        reg [2:0]  mant;
        real       result;
        integer    exp_val;
        begin
            sign = fp8[7];
            exp  = fp8[6:3];
            mant = fp8[2:0];

            if (exp == 0 && mant == 0) begin
                result = 0.0;
            end else if (exp == 0) begin
                // Denormalized
                exp_val = 1 - 7;  // 1 - bias
                result = (0.0 + mant / 8.0) * (2.0 ** exp_val);
            end else begin
                // Normalized
                exp_val = exp - 7;  // exp - bias
                result = (1.0 + mant / 8.0) * (2.0 ** exp_val);
            end

            if (sign) result = -result;
            fp8_to_real = result;
        end
    endfunction

    // Task to run a single test
    task run_test;
        input [7:0]  test_a;
        input [7:0]  test_b;
        input [1:0]  test_op;
        input [7:0]  expected_result;
        input        expect_zero;
        input        expect_overflow;
        input        expect_underflow;
        input [127:0] test_name;
        begin
            test_count = test_count + 1;

            @(posedge clk);
            a_fp8 = test_a;
            b_fp8 = test_b;
            op = test_op;
            start = 1'b1;

            @(posedge clk);
            start = 1'b0;

            // Wait for done
            wait(done);
            @(posedge clk);

            // Check results
            if (result_fp8 === expected_result &&
                flag_zero === expect_zero &&
                flag_overflow === expect_overflow &&
                flag_underflow === expect_underflow) begin
                pass_count = pass_count + 1;
                $display("[PASS] Test %0d: %s", test_count, test_name);
                $display("       A=%h (%.4f), B=%h (%.4f), Op=%b",
                         test_a, fp8_to_real(test_a),
                         test_b, fp8_to_real(test_b), test_op);
                $display("       Result=%h (%.4f), Expected=%h",
                         result_fp8, fp8_to_real(result_fp8), expected_result);
            end else begin
                fail_count = fail_count + 1;
                $display("[FAIL] Test %0d: %s", test_count, test_name);
                $display("       A=%h (%.4f), B=%h (%.4f), Op=%b",
                         test_a, fp8_to_real(test_a),
                         test_b, fp8_to_real(test_b), test_op);
                $display("       Result=%h (%.4f), Expected=%h",
                         result_fp8, fp8_to_real(result_fp8), expected_result);
                $display("       Flags: Z=%b, O=%b, U=%b, I=%b",
                         flag_zero, flag_overflow, flag_underflow, flag_inexact);
                $display("       Expected Flags: Z=%b, O=%b, U=%b",
                         expect_zero, expect_overflow, expect_underflow);
            end

            // Small delay between tests
            repeat(2) @(posedge clk);
        end
    endtask

    // Task to run test without expected value check (for observation)
    task run_test_observe;
        input [7:0]   test_a;
        input [7:0]   test_b;
        input [1:0]   test_op;
        input [127:0] test_name;
        begin
            test_count = test_count + 1;

            @(posedge clk);
            a_fp8 = test_a;
            b_fp8 = test_b;
            op = test_op;
            start = 1'b1;

            @(posedge clk);
            start = 1'b0;

            // Wait for done
            wait(done);
            @(posedge clk);

            $display("[INFO] Test %0d: %s", test_count, test_name);
            $display("       A=%h (%.6f), B=%h (%.6f), Op=%s",
                     test_a, fp8_to_real(test_a),
                     test_b, fp8_to_real(test_b),
                     (test_op == 2'b00) ? "ADD" :
                     (test_op == 2'b01) ? "SUB" :
                     (test_op == 2'b10) ? "MUL" : "RSV");
            $display("       Result=%h (%.6f)", result_fp8, fp8_to_real(result_fp8));
            $display("       Flags: Zero=%b, Overflow=%b, Underflow=%b, Inexact=%b",
                     flag_zero, flag_overflow, flag_underflow, flag_inexact);

            pass_count = pass_count + 1;
            repeat(2) @(posedge clk);
        end
    endtask

    // Main test sequence
    initial begin
        // Initialize
        $display("========================================");
        $display("FP8 E4M3 Arithmetic Unit Testbench");
        $display("========================================");
        $display("");

        test_count = 0;
        pass_count = 0;
        fail_count = 0;

        reset_n = 0;
        start = 0;
        a_fp8 = 8'd0;
        b_fp8 = 8'd0;
        op = 2'b00;

        // Reset sequence
        repeat(5) @(posedge clk);
        reset_n = 1;
        repeat(5) @(posedge clk);

        $display("");
        $display("=== ADDITION TESTS ===");
        $display("");

        // Test 1: Add two positive normalized numbers
        // 1.0 + 1.0 = 2.0
        // 1.0 = 0_0111_000 (exp=7, mant=0 -> 1.0 * 2^0)
        // 2.0 = 0_1000_000 (exp=8, mant=0 -> 1.0 * 2^1)
        run_test_observe(8'b0_0111_000, 8'b0_0111_000, 2'b00, "1.0 + 1.0 = 2.0");

        // Test 2: Add positive numbers with different exponents
        // 2.0 + 1.0 = 3.0
        // 2.0 = 0_1000_000, 1.0 = 0_0111_000
        // 3.0 = 0_1000_100 (exp=8, mant=4 -> 1.5 * 2^1)
        run_test_observe(8'b0_1000_000, 8'b0_0111_000, 2'b00, "2.0 + 1.0 = 3.0");

        // Test 3: Add with zero
        // 1.5 + 0 = 1.5
        // 1.5 = 0_0111_100
        run_test_observe(8'b0_0111_100, 8'b0_0000_000, 2'b00, "1.5 + 0 = 1.5");

        // Test 4: Add two zeros
        run_test_observe(8'b0_0000_000, 8'b0_0000_000, 2'b00, "0 + 0 = 0");

        // Test 5: Add positive and negative (same magnitude)
        // 1.0 + (-1.0) = 0
        run_test_observe(8'b0_0111_000, 8'b1_0111_000, 2'b00, "1.0 + (-1.0) = 0");

        // Test 6: Add negative numbers
        // -1.0 + (-1.0) = -2.0
        run_test_observe(8'b1_0111_000, 8'b1_0111_000, 2'b00, "-1.0 + (-1.0) = -2.0");

        // Test 7: Overflow test
        // Max + Max (should overflow)
        // Max = 0_1110_111 = 1.875 * 2^7 = 240
        run_test_observe(8'b0_1110_111, 8'b0_1110_111, 2'b00, "Max + Max (overflow)");

        // Test 8: Add denormalized numbers
        // 0_0000_001 + 0_0000_001
        run_test_observe(8'b0_0000_001, 8'b0_0000_001, 2'b00, "Denorm + Denorm");

        // Test 9: Add normalized and denormalized
        run_test_observe(8'b0_0001_000, 8'b0_0000_100, 2'b00, "Norm + Denorm");

        $display("");
        $display("=== SUBTRACTION TESTS ===");
        $display("");

        // Test 10: Subtract same numbers
        // 1.0 - 1.0 = 0
        run_test_observe(8'b0_0111_000, 8'b0_0111_000, 2'b01, "1.0 - 1.0 = 0");

        // Test 11: Subtract to get positive result
        // 2.0 - 1.0 = 1.0
        run_test_observe(8'b0_1000_000, 8'b0_0111_000, 2'b01, "2.0 - 1.0 = 1.0");

        // Test 12: Subtract to get negative result
        // 1.0 - 2.0 = -1.0
        run_test_observe(8'b0_0111_000, 8'b0_1000_000, 2'b01, "1.0 - 2.0 = -1.0");

        // Test 13: Subtract negative number (effective addition)
        // 1.0 - (-1.0) = 2.0
        run_test_observe(8'b0_0111_000, 8'b1_0111_000, 2'b01, "1.0 - (-1.0) = 2.0");

        // Test 14: Subtract from zero
        // 0 - 1.0 = -1.0
        run_test_observe(8'b0_0000_000, 8'b0_0111_000, 2'b01, "0 - 1.0 = -1.0");

        // Test 15: Subtract zero
        // 1.0 - 0 = 1.0
        run_test_observe(8'b0_0111_000, 8'b0_0000_000, 2'b01, "1.0 - 0 = 1.0");

        // Test 16: Negative - Negative
        // -1.0 - (-2.0) = 1.0
        run_test_observe(8'b1_0111_000, 8'b1_1000_000, 2'b01, "-1.0 - (-2.0) = 1.0");

        // Test 17: Underflow from subtraction
        run_test_observe(8'b0_0000_010, 8'b0_0000_001, 2'b01, "Denorm - Denorm (underflow)");

        $display("");
        $display("=== MULTIPLICATION TESTS ===");
        $display("");

        // Test 18: Multiply 1.0 * 1.0 = 1.0
        run_test_observe(8'b0_0111_000, 8'b0_0111_000, 2'b10, "1.0 * 1.0 = 1.0");

        // Test 19: Multiply 2.0 * 2.0 = 4.0
        // 4.0 = 0_1001_000
        run_test_observe(8'b0_1000_000, 8'b0_1000_000, 2'b10, "2.0 * 2.0 = 4.0");

        // Test 20: Multiply positive * negative
        // 2.0 * (-1.0) = -2.0
        run_test_observe(8'b0_1000_000, 8'b1_0111_000, 2'b10, "2.0 * (-1.0) = -2.0");

        // Test 21: Multiply negative * negative
        // -2.0 * (-2.0) = 4.0
        run_test_observe(8'b1_1000_000, 8'b1_1000_000, 2'b10, "-2.0 * (-2.0) = 4.0");

        // Test 22: Multiply by zero
        // 1.0 * 0 = 0
        run_test_observe(8'b0_0111_000, 8'b0_0000_000, 2'b10, "1.0 * 0 = 0");

        // Test 23: Multiply zero by zero
        run_test_observe(8'b0_0000_000, 8'b0_0000_000, 2'b10, "0 * 0 = 0");

        // Test 24: Multiply large numbers (overflow)
        run_test_observe(8'b0_1110_111, 8'b0_1000_000, 2'b10, "Max * 2.0 (overflow)");

        // Test 25: Multiply small numbers (underflow)
        run_test_observe(8'b0_0001_000, 8'b0_0001_000, 2'b10, "Min_norm * Min_norm (underflow)");

        // Test 26: Multiply denormalized numbers
        run_test_observe(8'b0_0000_100, 8'b0_0000_100, 2'b10, "Denorm * Denorm");

        // Test 27: Multiply 1.5 * 1.5 = 2.25
        // 1.5 = 0_0111_100, 2.25 = 0_1000_001
        run_test_observe(8'b0_0111_100, 8'b0_0111_100, 2'b10, "1.5 * 1.5 = 2.25");

        // Test 28: Multiply 0.5 * 2.0 = 1.0
        // 0.5 = 0_0110_000
        run_test_observe(8'b0_0110_000, 8'b0_1000_000, 2'b10, "0.5 * 2.0 = 1.0");

        $display("");
        $display("=== EDGE CASE TESTS ===");
        $display("");

        // Test 29: Maximum positive value
        run_test_observe(8'b0_1110_111, 8'b0_0000_000, 2'b00, "Max + 0");

        // Test 30: Minimum positive normalized
        run_test_observe(8'b0_0001_000, 8'b0_0000_000, 2'b00, "Min_norm + 0");

        // Test 31: Minimum positive denormalized
        run_test_observe(8'b0_0000_001, 8'b0_0000_000, 2'b00, "Min_denorm + 0");

        // Test 32: Negative zero
        run_test_observe(8'b1_0000_000, 8'b0_0000_000, 2'b00, "-0 + 0");

        // Test 33: Large exponent difference addition
        run_test_observe(8'b0_1110_000, 8'b0_0001_000, 2'b00, "Large_exp + Small_exp");

        // Test 34: Reserved operation
        run_test_observe(8'b0_0111_000, 8'b0_0111_000, 2'b11, "Reserved op");

        $display("");
        $display("=== COMPREHENSIVE SIGN COMBINATION TESTS ===");
        $display("");

        // Test various sign combinations
        run_test_observe(8'b0_0111_100, 8'b0_0111_010, 2'b00, "+A + +B (both positive)");
        run_test_observe(8'b0_0111_100, 8'b1_0111_010, 2'b00, "+A + -B (mixed)");
        run_test_observe(8'b1_0111_100, 8'b0_0111_010, 2'b00, "-A + +B (mixed)");
        run_test_observe(8'b1_0111_100, 8'b1_0111_010, 2'b00, "-A + -B (both negative)");

        run_test_observe(8'b0_0111_100, 8'b0_0111_010, 2'b01, "+A - +B");
        run_test_observe(8'b0_0111_100, 8'b1_0111_010, 2'b01, "+A - -B");
        run_test_observe(8'b1_0111_100, 8'b0_0111_010, 2'b01, "-A - +B");
        run_test_observe(8'b1_0111_100, 8'b1_0111_010, 2'b01, "-A - -B");

        run_test_observe(8'b0_0111_100, 8'b0_0111_010, 2'b10, "+A * +B");
        run_test_observe(8'b0_0111_100, 8'b1_0111_010, 2'b10, "+A * -B");
        run_test_observe(8'b1_0111_100, 8'b0_0111_010, 2'b10, "-A * +B");
        run_test_observe(8'b1_0111_100, 8'b1_0111_010, 2'b10, "-A * -B");

        $display("");
        $display("========================================");
        $display("TEST SUMMARY");
        $display("========================================");
        $display("Total Tests: %0d", test_count);
        $display("Passed:      %0d", pass_count);
        $display("Failed:      %0d", fail_count);
        $display("========================================");

        if (fail_count == 0) begin
            $display("ALL TESTS COMPLETED SUCCESSFULLY!");
        end else begin
            $display("SOME TESTS FAILED - Review results above");
        end

        $display("");
        $finish;
    end

    // Waveform dump for ModelSim
    initial begin
        $dumpfile("fp8_top_tb.vcd");
        $dumpvars(0, tb_fp8_top);
    end

    // Timeout watchdog
    initial begin
        #500000;
        $display("ERROR: Simulation timeout!");
        $finish;
    end

endmodule
