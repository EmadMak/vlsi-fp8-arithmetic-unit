// fp8_pkg.vh
// Constants and definitions for FP8 E4M3 arithmetic unit
// FP8 format: [7] sign | [6:3] exponent (bias=7) | [2:0] mantissa

`ifndef FP8_PKG_VH
`define FP8_PKG_VH

// FP8 E4M3 Format Parameters
`define FP8_WIDTH       8
`define FP8_SIGN_BIT    7
`define FP8_EXP_MSB     6
`define FP8_EXP_LSB     3
`define FP8_EXP_WIDTH   4
`define FP8_MANT_MSB    2
`define FP8_MANT_LSB    0
`define FP8_MANT_WIDTH  3
`define FP8_BIAS        7

// Exponent bounds
`define FP8_EXP_MAX     4'b1111  // 15
`define FP8_EXP_MIN     4'b0000  // 0 (denormalized)

// Operation codes
`define OP_ADD          2'b00
`define OP_SUB          2'b01
`define OP_MUL          2'b10
`define OP_RESERVED     2'b11

// Special values
`define FP8_ZERO_POS    8'b0_0000_000  // +0
`define FP8_ZERO_NEG    8'b1_0000_000  // -0
`define FP8_MAX_POS     8'b0_1110_111  // Max positive normalized
`define FP8_MAX_NEG     8'b1_1110_111  // Max negative normalized
`define FP8_MIN_NORM    8'b0_0001_000  // Min positive normalized

`endif
