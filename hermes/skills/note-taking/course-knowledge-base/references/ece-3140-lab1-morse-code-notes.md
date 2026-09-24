# ECE 3140 Lab 1 (Morse code) — timing math & ARM debugging notes

Reusable notes from tutoring/reviewing ECE 3140 Lab 1A (FRDM-KL46Z,
Cortex-M0+, GNU non-unified ARM assembly). The clock/cycle-cost math below
recurs for any timing-critical delay loop in this course's future labs, not
just this one.

## Deriving a busy-wait delay constant on Cortex-M0+ (KL46Z)

1. **Core clock frequency isn't given — derive or verify it, don't assume.**
   If the lab's `main` never calls a clock-configuration routine (only a port
   clock gate like `SCGC5`), the core runs at the SDK startup default. On the
   KL46Z that's MCG **FEI** mode: internal 32.768 kHz reference × FLL
   multiplier 640 = **~20.97 MHz** (`OUTDIV1` defaults to divide-by-1). Verify
   this against the `SystemCoreClock` global in a debug session rather than
   trusting the derivation blindly — clock-tree assumptions are exactly where
   these calculations go wrong.
2. **Cycle cost of a `SUBS`/`BNE` busy-wait loop on Cortex-M0+:** `SUBS` = 1
   cycle; `BNE` = 2 cycles when taken, 1 when not (Thumb-1, no branch
   predictor). Steady-state loop cost ≈ **3 cycles/iteration**. `BL`/`PUSH`/
   `POP`/`LDR =literal` overhead per call is a few cycles — negligible against
   a multi-million-iteration loop (<0.001% error), safe to ignore.
3. **Solve for iteration count N** given target time `T` (seconds) and clock
   `f` (Hz): `N ≈ (T × f) / 3`. Target the *middle* of a tolerance window, not
   an edge — e.g. for a 0.3–0.8s window, aim for ~0.5s so measurement error
   doesn't push you outside the range in either direction.
4. **For an exact ratio requirement between two durations** (e.g. "a dash is
   3× a dot"), don't hand-tune two independent constants — implement the
   longer duration as N chained calls to the shorter delay routine. This way
   the ratio holds exactly regardless of any error in the underlying
   clock-frequency assumption; only the absolute base duration needs
   empirical correction.
5. **Calibrate empirically, don't trust the math alone.** Flash the board,
   measure actual on-time (phone slow-motion video against a stopwatch is
   sufficient for tolerances measured in tenths of a second), then correct:
   `new_count = old_count × (target_time / measured_time)`. One or two
   correction rounds suffice since count scales linearly with time.

## Recurring ARM assembly bugs seen in student code

- **`B target` used where `BL target` (call) was intended.** `B` is an
  unconditional *jump* — it does not save a return address. If a routine does
  `B some_other_routine` intending "call it and continue," control never
  returns to the line after the `B`; instead, when `some_other_routine`
  eventually does `BX LR`, it returns to whoever called the *original*
  routine (since `LR` was never overwritten by the plain `B`). Symptom: a
  wrapper meant to chain N sub-delays only executes the first one. Fix: use
  `BL` for every "call and return here" step; reserve `B` for actual
  unconditional jumps (e.g. jumping to a shared loop exit).
- **A shared code path assumed order was fixed, but two cases need opposite
  order.** E.g. Morse-code symbol emission needs "dots then dashes" for one
  digit range and "dashes then dots" for the other, but a naive
  implementation always falls through the same `dot_loop` → `dash_loop`
  sequence regardless of which case set the counts — silently producing the
  wrong pattern for exactly the digits where order matters (bugs like this
  hide when testing only a digit where one count is zero, since order is
  moot in that case). **Fix pattern:** set an explicit register as an
  order-flag (e.g. `MOVS R7, #1` for "dashes first") using the same
  `MOVS`/`CMP`/conditional-branch idiom already used for argument-passing and
  digit dispatch, then branch to a start point that respects the flag *and*
  give each loop its own end-of-loop check (via the same flag) to jump into
  the *other* loop rather than always falling through to one shared exit.
  Also verify the flag register isn't clobbered by any function called from
  inside the loop body (check every `PUSH`/`POP` set, not just the obvious
  scratch registers).
- **Template discipline:** many autograders (this course included) deduct
  points for edits outside the marked "write your code below/above this
  line" region. If a delay-tuning constant or other new `.equ`/data needs to
  exist, put it *inside* the editable region even if conceptually it reads
  like setup — do not add lines above the marker just because they resemble
  the given fixed constants block.
