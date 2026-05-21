# Asynchronous FIFO — RTL Design & Verification

![Language](https://img.shields.io/badge/Language-Verilog--2001-blue)
![Tool](https://img.shields.io/badge/Tool-Xilinx%20Vivado-orange)
![Simulation](https://img.shields.io/badge/Simulation-Passing%205%2F5-brightgreen)
![CDC](https://img.shields.io/badge/CDC-Gray%20Code%20%2B%202FF%20Sync-blueviolet)
![License](https://img.shields.io/badge/License-MIT-lightgrey)

A fully parameterized, synthesizable **Asynchronous FIFO** (First-In First-Out buffer) designed in Verilog-2001. The design implements safe **Clock Domain Crossing (CDC)** using Gray code pointers and dual flip-flop synchronizers — the industry-standard technique for metastability-free inter-clock data transfer. The complete RTL-to-verification flow was executed in Xilinx Vivado.

---

## Table of Contents

1. [What is an Asynchronous FIFO?](#1-what-is-an-asynchronous-fifo)
2. [Scope of This Project](#2-scope-of-this-project)
3. [Architecture](#3-architecture)
4. [Module Breakdown](#4-module-breakdown)
5. [CDC Strategy — The Core Challenge](#5-cdc-strategy--the-core-challenge)
6. [Full & Empty Flag Logic](#6-full--empty-flag-logic)
7. [Design Parameters & Ports](#7-design-parameters--ports)
8. [Testbench Methodology](#8-testbench-methodology)
9. [Applications](#9-applications)
10. [Project File Structure](#10-project-file-structure)
11. [How to Simulate in Vivado](#11-how-to-simulate-in-vivado)
12. [References](#12-references)

---

## 1. What is an Asynchronous FIFO?

In digital systems, data frequently needs to move between two subsystems that run on **completely independent clocks** — for example, a processor writing data at 100 MHz while a peripheral reads it at 75 MHz. A simple register or synchronous FIFO cannot be used here because the clocks have no defined phase relationship and may even have different frequencies or jitter characteristics.

An **Asynchronous FIFO** solves this by acting as an elastic buffer between the two clock domains. The write side operates entirely in the **write clock (wclk) domain**, the read side operates entirely in the **read clock (rclk) domain**, and the two sides communicate only through carefully designed **Clock Domain Crossing (CDC)** logic.

The fundamental challenges this design must solve are:

- **Metastability** — when a signal generated in one clock domain is sampled by a flip-flop clocked by an unrelated clock, the output may not resolve to a valid logic level within the required setup/hold window. This is a physical phenomenon that cannot be eliminated, only managed.
- **Correct full/empty detection** — the write side must know when the FIFO is full to stop writing; the read side must know when it is empty to stop reading. Both conditions require comparing pointers that live in different clock domains, which must be done without introducing glitches or false flags.

---

## 2. Scope of This Project

This project covers the following:

- **RTL Design** of a parameterized async FIFO in Verilog-2001, structured as a hierarchy of submodules
- **CDC Implementation** using Gray code pointer encoding and 2-flip-flop synchronizers with proper Xilinx `ASYNC_REG` attributes
- **Full and Empty flag generation** using the standard MSB-inversion technique for Gray code comparison
- **Functional Verification** using a self-checking, scoreboard-based testbench that exercises write, read, and drain scenarios across two asynchronous clocks (100 MHz write, 75 MHz read)
- **Synthesis-ready code** following best practices for Xilinx FPGA implementation

The design is intentionally kept at the behavioral/RTL level for clarity and portability. It does not target a specific FPGA device or include physical constraints (XDC), making it easily adaptable to any Xilinx or non-Xilinx platform.

---

## 3. Architecture

The design is organized as a top-level wrapper (`async_fifo`) that connects five submodules. The key structural principle is that **no combinational logic crosses clock domains** — only registered Gray code pointer values are allowed to cross, and only through dedicated synchronizer chains.

```
                   ┌─────────────────────────────────────────────────────────────────┐
                   │                       async_fifo (top)                          │
                   │                                                                 │
  ┌────────────────┼──────────────────────┐   ┌──────────────────────────────────── ┤
  │   wclk domain  │                      │   │        rclk domain                  │
  │                │                      │   │                                     │
  │  ┌─────────────────────┐              │   │           ┌─────────────────────┐   │
  │  │   wptr_generator    │              │   │           │   rptr_generator    │   │
  │  │                     │              │   │           │                     │   │
  │  │  bin counter →      │◄─────────────┼───┼───────────┤  bin counter →      │   │
  │  │  Gray encode        │  gray_rptr   │   │           │  Gray encode        │   │
  │  │                     │   _sync      │   │  gray_    │                     │   │
  │  │  Generates: full    │              │   │  wptr     │  Generates: empty   │   │
  │  │  bin_wptr (address) │              │   │  _sync    │  bin_rptr (address) │   │
  │  └──────────┬──────────┘              │   │           └──────────┬──────────┘   │
  │             │ gray_wptr               │   │                      │ gray_rptr    │
  │             │                         │   │                      │              │
  │             ▼                         │   │                      ▼              │
  │  ┌─────────────────────┐              │   │           ┌─────────────────────┐   │
  │  │      cdc_sync       │◄─────────────┼───┼───────────┤      cdc_sync       │   │
  │  │  (gray_rptr →wclk)  │  gray_rptr   │   │ gray_wptr │  (gray_wptr →rclk)  │   │
  │  │                     │  from rclk   │   │ from wclk │                     │   │
  │  │  2-FF synchronizer  │  domain      │   │ domain    │  2-FF synchronizer  │   │
  │  └─────────────────────┘              │   │           └─────────────────────┘   │
  │                                       │   │                                     │
  └────────────────┬──────────────────────┘   └─────────────────────┬───────────── ┘
                   │ bin_wptr, w_en, wclk                            │ bin_rptr
                   │                                                 │
                   │          ┌──────────────────────┐              │
                   └─────────►│      fifo_memory     │◄─────────────┘
                              │                      │
                              │  Dual-port SRAM      │
                              │  Write: wclk sync    │──────► data_out
                              │  Read:  async        │
                              └──────────────────────┘
```

### Data flow summary

1. The **write side** increments a binary write pointer on each valid write, converts it to Gray code (`gray_wptr`), and registers it on `wclk`.
2. `gray_wptr` is passed through a 2-FF synchronizer clocked by `rclk` to produce `gray_wptr_sync`, which is safe to use in the read domain for **empty detection**.
3. The **read side** similarly maintains a binary read pointer, converts it to `gray_rptr`, and registers it on `rclk`.
4. `gray_rptr` is synchronized to `wclk` domain to produce `gray_rptr_sync`, used for **full detection**.
5. Both binary pointers (never synchronized — they are only used locally) index into the **dual-port SRAM** for write and read addressing.

---

## 4. Module Breakdown

### `async_fifo` — Top-level (`async_fifo.v`)

The structural top. Its only job is to wire together the five submodules correctly. It declares the internal Gray code pointer buses and the synchronized versions, and connects the two `cdc_sync` instances in the correct direction (rptr → wclk, wptr → rclk).

---

### `fifo_memory` — Dual-port SRAM (`fifo_memory.v`)

Implements the actual storage array as a 2D register array of size `[2^depth][width]`. The write port is synchronous (clocked on `wclk`, gated by `w_en & ~full`). The read port is **asynchronous** (combinational), meaning `data_out` reflects the memory at `bin_rptr` without any additional clock edge — which is appropriate since the read pointer itself is registered in the rclk domain.

---

### `wptr_generator` — Write Pointer & Full Flag (`wptr_generator.v`)

Maintains a `(depth+1)`-bit binary write counter `w_ptr`. The extra MSB is the key to unambiguous full/empty detection — it allows the design to distinguish between a "pointer lapped" (full) condition and a "pointer aligned" (empty) condition even when the lower address bits are identical.

On each `wclk` edge, if `w_en` is asserted and `full` is not, the counter increments. The next counter value is Gray-encoded using the standard XOR formula:

```
gray = binary ^ (binary >> 1)
```

The `full` flag is registered (not combinational) to avoid glitches at the output.

---

### `rptr_generator` — Read Pointer & Empty Flag (`rptr_generator.v`)

Structurally mirrors `wptr_generator`. Maintains a `(depth+1)`-bit binary read counter, Gray-encodes it, and compares with the synchronized write pointer to generate the `empty` flag. The FIFO initializes to the empty state on reset (`empty = 1`), which is the safe default.

---

### `cdc_sync` — 2-FF Synchronizer (`sync_ff.v`)

A parameterized, `WIDTH`-bit wide two flip-flop synchronizer. The first stage (`ff1`) is allowed to go metastable; the second stage (`ff2`) provides the resolved, stable output to the destination domain. Both registers carry the Xilinx `(* ASYNC_REG = "TRUE" *)` attribute, which instructs the Vivado placer to:

- Place `ff1` and `ff2` in the same slice (minimizing routing delay between them)
- Disable optimizations that could separate them
- Report them correctly in CDC analysis (Vivado's `report_cdc`)

This module is instantiated **twice** in the top level — once per crossing direction.

---

## 5. CDC Strategy — The Core Challenge

### Why not just synchronize binary pointers?

A binary pointer changes **multiple bits simultaneously** during certain increments (e.g., `0111 → 1000` flips all four bits at once). If this transition is sampled by a synchronizer, different bits may resolve at different times, and the destination domain could see a completely invalid intermediate value — for example, `1010` — which is neither the old nor new pointer value. This leads to incorrect flag assertions and potential data corruption.

### Why Gray code works

Gray code is constructed such that **only one bit changes between any two consecutive values**. This means:

- At worst, the synchronizer samples a transition in progress on exactly one bit
- The destination domain sees either the old or new pointer value — never a spurious intermediate
- A one-cycle delay in pointer propagation is acceptable (it makes the full/empty flags slightly conservative, which is safe)

### The 2-FF synchronizer and metastability

Metastability cannot be eliminated — it is a fundamental consequence of violating setup/hold times. The 2-FF synchronizer manages it by giving the metastable output of `ff1` a full clock period of the destination clock to resolve before being sampled by `ff2`. The probability of `ff2` still being metastable after this resolution window is extremely low and calculable via the MTBF (Mean Time Between Failures) equation:

```
MTBF = exp(Tr / τ) / (f_clk × f_data × C)
```

Where `Tr` is the resolution time (one clock period here), `τ` is a device-specific time constant, and `C` is a device-specific amplitude constant. For modern FPGAs at typical operating frequencies, MTBF values are measured in thousands of years.

---

## 6. Full & Empty Flag Logic

### Empty detection (rclk domain)

```
empty = (gray_wptr_sync == gray_rptr_next)
```

The empty condition is when the read pointer has caught up with the write pointer — both Gray-encoded values are equal. This comparison is done using the **next** read pointer value (`gray_rptr_next`) so the flag updates in the same clock cycle as the pointer, with no extra latency. The FIFO powers up empty (`empty = 1` on reset).

### Full detection (wclk domain)

```
full = (gray_wptr_next == { ~gray_rptr_sync[depth:depth-1], gray_rptr_sync[depth-2:0] })
```

Full occurs when the write pointer has lapped the read pointer — it is exactly one full revolution ahead. In Gray code, this corresponds to the next write pointer equaling the synchronized read pointer with its **top two bits inverted**. This specific bit manipulation correctly identifies the wrap-around condition while remaining entirely within Gray code arithmetic. Flipping only the top two bits (not one, not all) is the precise condition derived from the (depth+1)-bit pointer construction.

Both flags are **registered** outputs — they are computed from combinational logic but stored in a flip-flop at the clock edge. This prevents glitches from propagating to the write-enable or read-enable logic of the surrounding system.

---

## 7. Design Parameters & Ports

### Parameters

| Parameter | Default | Meaning |
|-----------|---------|---------|
| `width` | `4` | Data bus width in bits |
| `depth` | `4` | Address width; FIFO holds **2^depth** entries (default: 16 entries) |

The pointer width is always `depth+1` bits internally to support the full/empty disambiguation technique.

### Ports — `async_fifo` top level

| Port | Dir | Width | Clock Domain | Description |
|------|-----|-------|--------------|-------------|
| `wclk` | In | 1 | — | Write clock |
| `rclk` | In | 1 | — | Read clock (independent of wclk) |
| `rst` | In | 1 | Async | Active-low asynchronous reset; resets both domains |
| `w_en` | In | 1 | wclk | Write enable; ignored when `full = 1` |
| `r_en` | In | 1 | rclk | Read enable; ignored when `empty = 1` |
| `data_in` | In | `width` | wclk | Write data |
| `data_out` | Out | `width` | rclk | Read data (asynchronous read from SRAM) |
| `full` | Out | 1 | wclk | High when FIFO cannot accept more data |
| `empty` | Out | 1 | rclk | High when FIFO has no data to provide |

---

## 8. Testbench Methodology

The testbench (`tb_async_fifo`) is written as a **self-checking verification environment** with a built-in scoreboard. It does not require manual waveform inspection to determine correctness — the simulation prints a structured pass/fail report to the console.

### Clock setup

Two independent clocks with a non-integer frequency ratio are used deliberately to stress the CDC logic:

| Clock | Frequency | Period |
|-------|-----------|--------|
| `wclk` | 100 MHz | 10 ns |
| `rclk` | 75 MHz | ~13.33 ns |

The non-integer ratio (4:3) means the clocks drift relative to each other continuously, exercising a wide variety of sampling phases across the synchronizer over the course of simulation.

### Test sequence

| Phase | Description |
|-------|-------------|
| Reset | Active-low reset held for 50 ns (5 wclk cycles), then released. 30 ns settle time before any transactions. |
| Burst write | 4 words (`0xA`, `0xB`, `0xC`, `0xD`) written on consecutive `wclk` edges with `w_en = 1`. |
| CDC wait | A **level-sensitive wait** (`while (empty)`) blocks until the synchronized write pointer propagates to the rclk domain and `empty` deasserts. This avoids hardcoded delays that can cause race conditions. |
| Burst read | `r_en` is asserted; 4 consecutive `rclk` edges are used to clock out and verify all 4 words in order. |
| Drain check | After `r_en` is deasserted, the testbench waits 80 ns and verifies that `empty` has re-asserted, confirming the FIFO correctly reports it is drained. |
| Scoreboard | Total PASS and FAIL counts are printed. Simulation exits with `$finish`. |

### Expected simulation output

```
===== TEST: Write 4 words, read back and verify =====
[WRITE] data_in = 0xA
[WRITE] data_in = 0xB
[WRITE] data_in = 0xC
[WRITE] data_in = 0xD
[PASS]  data_out = 0xa  (expected 0xA)
[PASS]  data_out = 0xb  (expected 0xB)
[PASS]  data_out = 0xc  (expected 0xC)
[PASS]  data_out = 0xd  (expected 0xD)
[PASS]  FIFO empty after drain.

========================================
  RESULTS: 5 PASS | 0 FAIL
  ALL CHECKS PASSED
========================================
```

---

## 9. Applications

Asynchronous FIFOs are ubiquitous in digital hardware wherever data crosses between independent clock domains. Some real-world use cases:

| Application | Write Domain | Read Domain |
|-------------|-------------|-------------|
| **USB to MCU interface** | USB PHY clock (48/60 MHz) | System bus clock |
| **DDR memory controller** | Memory clock (DRAM timing) | CPU/bus clock |
| **Ethernet MAC/PHY** | PHY receive clock (recovered) | MAC system clock |
| **PCIe endpoint** | PCIe lane clock | Application logic clock |
| **Audio codec interface** | Audio sample clock (e.g., 12.288 MHz) | DSP processor clock |
| **Camera sensor pipeline** | Pixel clock from sensor | ISP processing clock |
| **FPGA multi-clock designs** | Any fast domain | Any slow domain (or vice versa) |
| **SoC NoC (Network-on-Chip)** | Source tile clock | Destination tile clock |

In every case, the requirements are identical to what this design addresses: safe pointer crossing, glitch-free flags, and no data corruption under any clock phase relationship.

---

## 10. Project File Structure

```
async-fifo/
│
├── rtl/
│   ├── async_fifo.v          ← Top-level structural module
│   ├── fifo_memory.v         ← Dual-port synchronous-write / async-read SRAM
│   ├── wptr_generator.v      ← Write pointer (binary + Gray), full flag
│   ├── rptr_generator.v      ← Read pointer (binary + Gray), empty flag
│   └── sync_ff.v             ← Parameterized 2-FF CDC synchronizer (cdc_sync)
│
├── tb/
│   └── tb.v                  ← Self-checking testbench with scoreboard
│
└── README.md
```

---

## 11. How to Simulate in Vivado

### 1. Create a new project
- Open Vivado → **Create Project** → choose **RTL Project**
- When prompted for sources, add all five `.v` files from `rtl/` as **Design Sources**
- Add `tb/tb.v` as a **Simulation Source**
- Do not specify a board/part if only simulating

### 2. Set the simulation top
- In the Sources panel, right-click `tb_async_fifo` → **Set as Top** (under Simulation Sources)

### 3. Run behavioral simulation
- Flow Navigator → **Simulation** → **Run Simulation** → **Run Behavioral Simulation**
- The Tcl console will show the `[WRITE]` / `[PASS]` / `[FAIL]` messages as the simulation runs

### 4. View waveforms
- In the waveform window, click **Add → Add Wave Group** or type in the Tcl console:
  ```tcl
  add_wave /tb_async_fifo/*
  run all
  ```
- Use **Zoom Fit (Ctrl+Shift+F)** to see the full simulation timeline
- Key signals to observe: `wclk`, `rclk`, `rst`, `w_en`, `r_en`, `data_in`, `data_out`, `full`, `empty`

### 5. Optional — Run synthesis
- Change the top module to `async_fifo` (Design Sources)
- Flow Navigator → **Synthesis** → **Run Synthesis**
- After synthesis: **Open Synthesized Design** → **Schematic** to view the gate-level netlist
- Check **Report Utilization** and **Report Timing Summary** in the Reports panel

---

## 12. References

1. **Clifford E. Cummings** — *"Simulation and Synthesis Techniques for Asynchronous FIFO Design"*, SNUG San Jose 2002.  
   The foundational paper this design is based on. Covers Gray code pointer theory, full/empty flag derivation, and synthesis guidelines in depth.  
   Available at: http://www.sunburst-design.com/papers/CummingsSNUG2002SJ_FIFO1.pdf

2. **Clifford E. Cummings** — *"Synthesis and Scripting Techniques for Designing Multi-Asynchronous Clock Designs"*, SNUG San Jose 2001.  
   Companion paper covering broader CDC design methodology.  
   Available at: http://www.sunburst-design.com/papers/CummingsSNUG2001SJ_AsyncClk.pdf

3. **Xilinx UG901** — *Vivado Design Suite User Guide: Vivado Synthesis*.  
   Documents the `ASYNC_REG` attribute behaviour and synthesis directives used in `cdc_sync`.

4. **Xilinx UG906** — *Vivado Design Suite User Guide: Design Analysis and Closure Techniques*.  
   Covers `report_cdc` — Vivado's built-in CDC analysis tool that validates synchronizer placement.

5. **Pong P. Chu** — *FPGA Prototyping by Verilog Examples*, Wiley, 2008.  
   Chapter on FIFO design provides a clear pedagogical treatment of the pointer-based approach.

6. **IEEE Std 1800-2012** — *SystemVerilog Hardware Description Language*.  
   Reference for Verilog-2001 / SystemVerilog language constructs used in this design.

---

*Designed and verified using Xilinx Vivado. RTL written in Verilog-2001. CDC methodology follows SNUG 2002 industry standard.*
