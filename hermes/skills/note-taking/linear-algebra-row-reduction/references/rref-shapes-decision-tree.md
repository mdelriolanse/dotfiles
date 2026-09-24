# RREF Shapes: Decision Tree & Instant Classification

## Core Principle

After row-reducing to RREF (or even REF), the **shape** of the matrix—specifically where the staircase of pivots terminates and whether contradiction rows exist—completely determines whether the system has zero, one, or infinitely many solutions.

## Three Numbers Determine Everything

Extract these after row reduction to REF:

1. **Rank r** = number of pivots (non-zero rows in coefficient matrix)
2. **Variables n** = number of variable columns (before the `|` in augmented matrix)
3. **Contradictions** = any rows of form `[0 0 ... 0 | c]` where c ≠ 0?

## Four Outcome Cases

| r vs n | Contradiction? | Outcome | Solution Geometry |
|--------|---|---|---|
| r = n | NO | **UNIQUE SOLUTION** | Single point (0-dimensional) |
| r = n | YES | **INCONSISTENT** | Empty set |
| r < n | NO | **INFINITELY MANY** | Hyperplane of dimension n - r |
| r < n | YES | **INCONSISTENT** | Empty set |

## Decision Tree (Two Steps)

```
                    RREF matrix
                         |
          ┌──────────────┴──────────────┐
          |                             |
    Contradiction row [0|c], c ≠ 0?    No contradictions
          |                             |
         YES                            |
          |                    Compare r to n
        INC                            |
                         ┌─────────────┴─────────────┐
                         |                           |
                       r = n                       r < n
                         |                           |
                       UNIQUE                   INFINITELY MANY
                                               (n-r free variables)
```

**Process:**
1. Scan RREF for any row `[0 0 ... 0 | c]` with c ≠ 0 → if found, INCONSISTENT (stop)
2. Otherwise, count pivots (r) and variable columns (n) → apply table above

## The Staircase Interpretation

The "staircase" is the descending-right diagonal pattern of pivots.

**If staircase reaches the rightmost variable column (column n):**
- → r = n (full rank)
- → Every variable is determined
- → Look for contradictions; if none, unique solution

**If staircase stops before column n:**
- → r < n (rank deficiency)
- → Columns without pivots = free variables (n - r of them)
- → Look for contradictions; if none, infinitely many

## Free Variables Formula

$$\text{Number of free variables} = n - r$$

This is the **dimension of the solution set** (when consistent):
- n - r = 0 → a point
- n - r = 1 → a line
- n - r = 2 → a plane
- n - r = k → a k-dimensional hyperplane

## Practical Use (Instant Answer)

1. Row reduce to **REF** (stop here; RREF is optional for classification)
2. Count non-zero rows → r
3. Count variable columns → n
4. Scan for `[0 0 ... 0 | c]` with c ≠ 0
5. Look up (r, n, contradiction) in the four-case table → done

**No need to finish RREF** for consistency checks. REF is sufficient.

## Examples

### Example 1: Full Rank, Unique
```
1  0  0  | 5
0  1  0  | 3
0  0  1  | 2
```
r = 3, n = 3, no contradictions → **UNIQUE: x=5, y=3, z=2**

### Example 2: Rank Deficient, Infinitely Many
```
1  0  *  * | 5
0  1  *  * | 3
0  0  0  0 | 0
```
r = 2, n = 4, no contradictions → **INFINITELY MANY: 2 free variables (4-2=2)**

### Example 3: Rank Deficient, Inconsistent
```
1  0  *  * | 5
0  1  *  * | 3
0  0  0  0 | 7     ← Contradiction!
```
r = 2, n = 4, **but** `[0 0 0 0 | 7]` means 0 = 7 → **INCONSISTENT**

### Example 4: Full Rank, Inconsistent
```
1  0  0 | 5
0  1  0 | 3
0  0  0 | 2     ← Contradiction!
```
r = 2, n = 3, **and** `[0 0 0 | 2]` → **INCONSISTENT**

## Connection to Problem Types

- **Consistency with parameters** ("Find h, k so the system is consistent"):
  - Row reduce; set any contradiction rows to 0; solve for h, k

- **Solve the system** ("Find the general solution"):
  - Row reduce to RREF; apply decision tree; if infinitely many, identify free variables and extract solution vector

- **Span membership** ("Is y in Span{v₁, v₂, v₃}?"):
  - Translate to `[v₁ v₂ v₃ | y]` system; row reduce; apply decision tree with y's parameter
