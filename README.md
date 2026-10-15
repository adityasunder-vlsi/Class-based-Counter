# Class-Based SystemVerilog Testbench for a 4-bit Counter

A self-checking, constrained-random verification environment for a 4-bit synchronous counter, written in SystemVerilog using a layered, class-based architecture.

## Files

| File | Contents |
|---|---|
| `design.sv` | 4-bit counter (DUT) and `counter_if` interface |
| `testbench.sv` | `transaction`, `generator`, `driver`, `monitor`, `scoreboard`, `environment` classes and the `tb` top module |

## DUT Behaviour

| `rst` | `enable` | Next `count` |
|---|---|---|
| 1 | x | 0 |
| 0 | 1 | count + 1 (wraps 15 -> 0) |
| 0 | 0 | holds |

Synchronous reset, active high. Reset has priority over enable.

## Architecture

```
generator --mailbox--> driver --pins--> DUT --count--> monitor --mailbox--> scoreboard
    ^                                                                          
    +------------------ drv_done event (driver -> generator) -----------------+
```

`environment` builds and connects all components. `tb` provides the clock, interface, DUT and environment.

### Components

- **transaction**: data packet with random `rst` and `enable` (constrained: `rst` about 10% high, `enable` about 70% high) and an observed `count`.
- **generator**: creates `num_transactions` random transactions, sends each to the driver through a mailbox, and waits for `drv_done` before sending the next. Fires `done` at the end.
- **driver**: applies a reset sequence, then drives each transaction onto the DUT through a virtual interface for exactly one clock and clears the inputs. Fires `drv_done`.
- **monitor**: passive. Samples `rst`, `enable` and `count` on every clock edge and sends them to the scoreboard.
- **scoreboard**: self-checking. Keeps an expected count, compares it with the DUT's `count`, then updates the expectation from the observed `rst` and `enable`. Reports PASS/FAIL totals.
- **environment**: creates mailboxes, events and components, then runs `pre_test` (reset), `test` (fork all components) and `post_test` (wait for `done`, drain, report, `$finish`).

## Approach and Logic

1. **Stimulus**: constrained-random `rst` and `enable` values give a mix of counting, holding and resetting.
2. **Driving**: inputs are applied with non-blocking assignments and held for one clock edge only, so each transaction affects the counter exactly once.
3. **Monitoring**: sampling every cycle means no timing guesses, and idle cycles also check that the counter holds its value.
4. **Checking**: the count seen at a clock edge is the result of the previous edge. The scoreboard therefore checks first, then updates the expected value:
   - `rst` -> expected = 0
   - `enable` -> expected = expected + 1
   - otherwise -> expected holds
5. **Comparison** uses `===`, so an `x` or `z` on the DUT output counts as a failure.
6. **Synchronization**: a mailbox carries data, and the `drv_done` event keeps the generator in step with the driver. The test finishes cleanly when the generator fires `done`.

## Simulation Output

50 random transactions:

```
[DRV] reset done at 55
[GEN] rst=1 enable=1 count=0 time=55
[DRV] rst=1 enable=1 count=0 time=65
[GEN] rst=0 enable=0 count=0 time=75
...
--------------------------------------
[SCO] PASS=104 FAIL=0
[SCO] TEST PASSED
--------------------------------------
$finish at simulation time 1105
```

The waveform shows `count` incrementing one clock after `enable` is high and returning to 0 one clock after `rst` is high, matching the expected behaviour.

## How to Run

Any SystemVerilog simulator with class and mailbox support works (for example VCS, Questa, Xcelium, or EDA Playground).

1. Add `design.sv` as the design file and `testbench.sv` as the testbench file.
2. Compile and run. The top module is `tb`.
3. Open `dump.vcd` to view the waveforms.

To change the test length, edit `env.gen.num_transactions` in `tb`.

## Possible Extensions

- Run longer tests to exercise the 15 -> 0 rollover.
- Add functional coverage (covergroups) and SVA assertions.
- Add directed tests, for example back-to-back resets.
- Convert to a UVM environment.
