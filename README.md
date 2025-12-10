# FP8 E4M3 Arithmetic Unit

A Verilog RTL implementation of an 8-bit floating-point arithmetic unit supporting addition, subtraction, and multiplication operations. The design follows the E4M3 FP8 format and is implemented without using datapath operators (`+`, `-`, `*`).

## Project Structure

```
vlsi-fp8-arithmetic-unit/
├── rtl/
│   ├── fp8_pkg.vh      # Constants and format definitions
│   ├── fp8_addsub.v    # Addition/subtraction unit
│   ├── fp8_mult.v      # Multiplication unit
│   └── fp8_top.v       # Top-level integration
├── tb/
│   └── tb_fp8_top.v    # Comprehensive testbench
├── docs/
│   └── report.tex      # LaTeX project report
└── README.md           # This file
```

## FP8 E4M3 Format

The E4M3 format uses 8 bits organized as:

| Bit Range | Field      | Width  | Description                          |
|-----------|------------|--------|--------------------------------------|
| [7]       | Sign (S)   | 1 bit  | 0 = positive, 1 = negative           |
| [6:3]     | Exponent   | 4 bits | Biased exponent, Bias = 7            |
| [2:0]     | Mantissa   | 3 bits | Fraction (implicit leading 1)        |

### Value Calculation

- **Normalized** (E ≠ 0): `Value = (-1)^S × (1 + M/8) × 2^(E-7)`
- **Denormalized** (E = 0): `Value = (-1)^S × (M/8) × 2^(-6)`

### Value Range

| Type            | Binary        | Decimal Value |
|-----------------|---------------|---------------|
| Max Positive    | `0_1110_111`  | 240.0         |
| Min Normalized  | `0_0001_000`  | 0.015625      |
| Min Denormalized| `0_0000_001`  | ~0.00195      |
| Zero            | `0_0000_000`  | 0.0           |

## Module Descriptions

### fp8_pkg.vh

Contains constant definitions for the FP8 format:

```verilog
`define FP8_WIDTH       8
`define FP8_SIGN_BIT    7
`define FP8_EXP_MSB     6
`define FP8_EXP_LSB     3
`define FP8_EXP_WIDTH   4
`define FP8_MANT_MSB    2
`define FP8_MANT_LSB    0
`define FP8_MANT_WIDTH  3
`define FP8_BIAS        7
```

Operation codes:
- `OP_ADD = 2'b00` - Addition
- `OP_SUB = 2'b01` - Subtraction
- `OP_MUL = 2'b10` - Multiplication
- `OP_RESERVED = 2'b11` - Reserved

### fp8_top.v

Top-level integration module with the following interface:

```verilog
module fp8_top (
    // Clock and reset
    input  wire       clk,
    input  wire       reset_n,      // Active-low reset

    // Control
    input  wire       start,        // Start operation
    output reg        done,         // Operation complete

    // Operands
    input  wire [7:0] a_fp8,        // Operand A
    input  wire [7:0] b_fp8,        // Operand B
    input  wire [1:0] op,           // Operation select

    // Result
    output reg  [7:0] result_fp8,   // Result

    // Status flags
    output reg        flag_zero,     // Result is zero
    output reg        flag_overflow, // Overflow occurred
    output reg        flag_underflow,// Underflow occurred
    output reg        flag_inexact   // Rounding occurred
);
```

**Operation:**
1. Assert `start` with valid operands and operation code
2. Wait for `done` signal (6 cycles for add/sub, 4 cycles for multiply)
3. Read `result_fp8` and status flags

### fp8_addsub.v

Floating-point addition and subtraction unit.

**Architecture (6-stage pipeline):**

1. **UNPACK** - Extract sign, exponent, mantissa; detect zeros/denormals
2. **ALIGN** - Compare exponents and determine shift amount
3. **COMPUTE** - Apply barrel shifter to align mantissas
4. **COMPUTE2** - Add or subtract aligned mantissas
5. **NORMALIZE** - Shift result and adjust exponent
6. **PACK** - Round and assemble final FP8 result

**Key Components:**

- `adder_Nbit` - Ripple-carry adders (4, 5, 8, 9-bit variants)
- `full_adder` - Single-bit adder using XOR/AND gates
- `barrel_shifter_right_8` - Two instances for shifting either operand
- `leading_zero_counter_8` - Priority encoder for normalization

**Key Design Features:**

- **Dual Barrel Shifters**: Allows shifting either operand A or B depending on exponent comparison
- **Split Computation**: COMPUTE applies alignment, COMPUTE2 performs arithmetic (ensures stable inputs)
- **9-bit Two's Complement**: Proper subtraction using `A + {1,~B} + 1` for correct results

**Algorithm:**
```
1. Unpack: Extract S_a, E_a, M_a and S_b, E_b, M_b
2. Add hidden bit to mantissas
3. Compare exponents: determine which operand to shift
4. Apply barrel shifter to smaller operand
5. If signs same: add mantissas
   If signs differ: subtract smaller from larger
6. Normalize: shift left/right, adjust exponent
7. Round to 3-bit mantissa
8. Pack: Combine sign, exponent, mantissa
```

### fp8_mult.v

Floating-point multiplication unit.

**Architecture (5-stage pipeline):**

1. **UNPACK** - Extract fields, detect zeros
2. **MULTIPLY** - Add exponents, multiply mantissas
3. **NORMALIZE** - Adjust product mantissa and exponent
4. **PACK** - Round and assemble result

**Key Components:**

- `adder_6bit` - For exponent addition (handles bias subtraction)
- `multiplier_4x4` - Shift-and-add multiplier for mantissas

**Algorithm:**
```
1. Sign_result = Sign_a XOR Sign_b
2. Exp_result = Exp_a + Exp_b - Bias
3. Mant_result = Mant_a × Mant_b (shift-and-add)
4. Normalize if needed
5. Round and pack result
```

**4x4 Multiplier Implementation:**
```verilog
// Partial products using AND gates
pp0 = b[0] ? {4'b0, a} : 8'd0;
pp1 = b[1] ? {3'b0, a, 1'b0} : 8'd0;
pp2 = b[2] ? {2'b0, a, 2'b0} : 8'd0;
pp3 = b[3] ? {1'b0, a, 3'b0} : 8'd0;

// Sum partial products using adders
product = pp0 + pp1 + pp2 + pp3;  // (using gate-level adders)
```

### Gate-Level Arithmetic

All arithmetic is implemented without `+`, `-`, `*` operators:

**Full Adder:**
```verilog
assign sum = a ^ b ^ cin;
assign cout = (a & b) | ((a ^ b) & cin);
```

**Two's Complement Subtraction:**
```verilog
// To compute a - b:
b_neg = ~b;           // One's complement
result = a + b_neg + 1;  // Add with carry-in = 1
```

**Comparison:**
```verilog
// a >= b if (a - b) produces no borrow
// Borrow = ~carry_out from subtraction
```

## Testbench

The testbench (`tb_fp8_top.v`) provides comprehensive verification:

### Test Categories

1. **Addition Tests**
   - Positive + Positive
   - Positive + Negative (cancellation)
   - Negative + Negative
   - Zero operand handling
   - Overflow conditions

2. **Subtraction Tests**
   - Same sign operands
   - Different sign operands (effective addition)
   - Result sign determination
   - Underflow conditions

3. **Multiplication Tests**
   - Sign combination (++ +- -+ --)
   - Zero multiplication
   - Overflow/underflow
   - Denormalized operands

4. **Edge Cases**
   - Maximum/minimum values
   - Denormalized numbers
   - Large exponent differences

### Running the Testbench

**ModelSim:**
```bash
cd vlsi-fp8-arithmetic-unit
vlib work
vlog -incr rtl/*.v rtl/*.vh tb/*.v
vsim -c tb_fp8_top -do "run -all"
```

**Icarus Verilog:**
```bash
cd vlsi-fp8-arithmetic-unit
iverilog -I rtl -o fp8_sim rtl/*.v tb/*.v
vvp fp8_sim
gtkwave fp8_top_tb.vcd  # View waveforms
```

### Expected Output

```
========================================
FP8 E4M3 Arithmetic Unit Testbench
========================================

=== ADDITION TESTS ===

[INFO] Test 1: 1.0 + 1.0 = 2.0
       A=38 (1.000000), B=38 (1.000000), Op=ADD
       Result=40 (2.000000)
       Flags: Zero=0, Overflow=0, Underflow=0, Inexact=0
...

========================================
TEST SUMMARY
========================================
Total Tests: 46
Passed:      46
Failed:      0
========================================
```

## Key Design Decisions

### Why No Datapath Operators?

This design constraint ensures:
1. Direct mapping to hardware gates without synthesis optimization
2. Educational clarity of floating-point arithmetic
3. Predictable and verifiable gate-level behavior

### Rounding

The design implements **round-to-nearest-even** (banker's rounding):
- Guard bit: First bit beyond mantissa precision
- Round bit: Second bit beyond precision
- Sticky bit: OR of all remaining bits

Round up if: `guard & (round | sticky | LSB_of_mantissa)`

### Overflow Handling

On overflow:
- Set `flag_overflow`
- Saturate result to maximum representable value (`0_1110_111` or `1_1110_111`)

### Underflow Handling

On underflow:
- Set `flag_underflow`
- Create denormalized result if possible, otherwise flush to zero

## Timing

**Addition/Subtraction** completes in **6 clock cycles**:

```
Cycle 1: UNPACK
Cycle 2: ALIGN
Cycle 3: COMPUTE (apply shift)
Cycle 4: COMPUTE2 (add/subtract)
Cycle 5: NORMALIZE
Cycle 6: PACK (done asserted)
```

**Multiplication** completes in **4 clock cycles**:

```
Cycle 1: UNPACK
Cycle 2: MULTIPLY
Cycle 3: NORMALIZE
Cycle 4: PACK (done asserted)
```

## File Dependencies

```
fp8_top.v
├── fp8_pkg.vh (included)
├── fp8_addsub.v
│   ├── fp8_pkg.vh (included)
│   ├── full_adder (defined internally)
│   ├── adder_4bit (defined internally)
│   ├── adder_5bit (defined internally)
│   ├── adder_8bit (defined internally)
│   ├── adder_9bit (defined internally)
│   ├── leading_zero_counter_8 (defined internally)
│   └── barrel_shifter_right_8 (x2, defined internally)
└── fp8_mult.v
    ├── fp8_pkg.vh (included)
    ├── adder_6bit (defined internally)
    ├── leading_zero_counter_8 (defined internally)
    └── multiplier_4x4 (defined internally)
```

## Synthesis Notes

For FPGA/ASIC synthesis:
1. The gate-level adders will be optimized by synthesis tools
2. Consider pipelining for higher clock frequencies
3. Barrel shifter can be replaced with dedicated shift resources

## Limitations

- No NaN or Infinity handling
- No division or square root
- Single-issue (one operation at a time)
- 6-cycle latency for add/sub, 4-cycle for multiply (not pipelined for throughput)
