# REF vs RREF: Checklist Comparison with Examples

## Side-by-Side Comparison

| Property | REF | RREF |
|----------|-----|------|
| **Leading entry rule** | Yes: pivot is strictly right of pivot above | Yes: same as REF |
| **Zeros below pivots** | Yes: required | Yes: required |
| **Zeros above pivots** | No: allowed | Yes: required |
| **Each pivot is 1** | No: pivot can be any nonzero | Yes: required |
| **Free variable identification** | Possible (but tedious) | Easy: non-pivot columns are free |
| **Back-substitution needed** | Yes: must solve for dependent vars | No: solution is nearly readable |
| **When to use** | Check consistency, identify pivot structure | Write general solution cleanly |

## Example: Building from the Same System

Start with **augmented matrix**:
```
[  1  -2  -1   3 | 0 ]
[ -2   4   5  -5 | 3 ]
[  3  -6  -6   8 | 2 ]
```

### Step 1: Forward Elimination → REF

After eliminating below the first pivot (column 1):
```
[  1  -2  -1   3 | 0 ]
[  0   0   3   1 | 3 ]
[  0   0  -3  -1 | 2 ]
```

After eliminating below the second pivot (column 3):
```
[  1  -2  -1   3 | 0 ]
[  0   0   3   1 | 3 ]
[  0   0   0   0 | 5 ]  ← INCONSISTENCY! Stop here.
```

**This is REF.** We can see:
- Row 1 pivot in column 1 ✓
- Row 2 pivot in column 3 ✓ (strictly to right of column 1)
- Zeros below pivots ✓
- Row 3 is a contradiction: 0 = 5 ✗ System is inconsistent

**Decision**: The system is already inconsistent, so we never reach RREF. REF was sufficient to make the determination.

---

## Example 2: Consistent System (Hypothetical)

Suppose the RHS of row 3 had been `0` instead of `5` (making it consistent):

```
[  1  -2  -1   3 | 0 ]
[  0   0   3   1 | 3 ]
[  0   0   0   0 | 0 ]
```

**This is REF.** Checklist:
- ✓ Zero row at the bottom
- ✓ Pivots in columns 1 and 3 (strictly increasing column indices)
- ✓ Zeros below pivots
- ✓ No contradiction rows

**Now continue to RREF** (Phase 2: Back Substitution)

### Step 2: Normalize the pivot in row 2

R₂ ÷ 3:
```
[  1  -2  -1   3  | 0 ]
[  0   0   1  1/3 | 1 ]
[  0   0   0   0  | 0 ]
```

### Step 3: Eliminate above the pivot in column 3

R₁ ← R₁ + R₂:
```
[  1  -2   0  10/3 | 1 ]
[  0   0   1   1/3 | 1 ]
[  0   0   0    0  | 0 ]
```

**This is RREF.** Checklist:
- ✓ REF properties all satisfied (leading entry rule, zeros below)
- ✓ Each pivot is 1 (row 1 col 1, row 2 col 3)
- ✓ Each pivot is isolated (column 1 only nonzero in row 1; column 3 only nonzero in row 2)
- ✓ Columns 2 and 4 have no pivots (these are free variables)

**From RREF, the solution is immediate**:
- Pivots: x₁, x₃ (dependent)
- Free: x₂, x₄
- General solution: x = x_p + s·v₁ + t·v₂ (see general-solution-extraction.md)

---

## Visual Recognition Guide

### **This is REF but NOT RREF**:
```
[  1   2  -1   3 | 5 ]
[  0   0   3   1 | 2 ]
[  0   0   0   2 | 4 ]
```

Why?
- ✓ Leading entry rule: 1 (col 1), then 3 (col 3), then 2 (col 4) — strictly right ✓
- ✓ Zeros below pivots ✓
- ✗ Pivot in row 2 is 3, not 1 (should be normalized)
- ✗ Pivot in row 3 is 2, not 1
- ✗ Column 1: entry above the 1 is allowed in REF, but RREF would zero it if there were a pivot above

→ **Stop here for consistency check. Continue to RREF only if needed for solution extraction.**

### **This is RREF**:
```
[  1   2   0   0 | 5 ]
[  0   0   1   0 | 2 ]
[  0   0   0   1 | 4 ]
```

Why?
- ✓ REF properties ✓
- ✓ All pivots are 1 ✓
- ✓ Column 1: only nonzero is the pivot (1 in row 1) ✓
- ✓ Column 3: only nonzero is the pivot (1 in row 2) ✓
- ✓ Column 4: only nonzero is the pivot (1 in row 3) ✓
- ✓ Column 2: no pivot, so it's free (x₂ is a free variable)

→ **RREF reached. Solution is readable directly or via back-substitution.**

---

## Decision Flowchart

```
Start: row-reduce the augmented matrix

         │
         ↓
    Done with forward elimination
    (all rows below each pivot are zero)?
         │
         NO → Continue eliminating
         │
         YES → You are at REF
             │
             ├─→ Is there a contradiction row [0 0 ... 0 | c], c ≠ 0?
             │   YES → STOP. System is inconsistent.
             │   NO → Continue to RREF (optional)
             │
             └─→ Do you need the general solution?
                 YES → Continue back-substitution (Phase 2) → RREF
                 NO → You're done with REF (consistency confirmed)
```

## When to Stop at Each Stage

| Goal | Stop At | Why |
|------|----------|-----|
| Check if system is **solvable** | REF | Can spot contradiction rows |
| Identify **free variables** | REF | Non-pivot columns are free |
| Find the **general solution** | RREF | Nearly readable, just substitute |
| Minimal row reduction | REF | Fewer operations, faster |
| Teaching or clarity | RREF | Canonical form, unambiguous |
