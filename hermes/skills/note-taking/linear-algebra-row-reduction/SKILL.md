---
name: linear-algebra-row-reduction
type: lesson
description: Row reduction, REF/RREF checklists, extracting solutions.
tags:
  - linear-algebra
  - row-reduction
  - echelon-form
  - rref
  - consistency
  - span
created: 2026-09-03
---

# Row Reduction and Echelon Forms: Concepts & Procedures

Use when solving linear systems via row reduction, checking consistency, extracting general solutions, or translating span membership into a system of equations. Covers the pedagogical approach: three lenses on consistency, procedural checklists for REF vs RREF, and how to read solutions from reduced forms.

## Understanding Consistency: Three Lenses

A **linear system is consistent** if it has at least one solution. An **inconsistent system** has no solutions. Understand this from multiple angles:

### Geometric Lens
- Each equation is a geometric object (line in 2D, plane in 3D, hyperplane in higher dimensions)
- **Consistent**: objects intersect (one point, infinitely many points, or coincide)
- **Inconsistent**: objects are parallel and never meet

### Algebraic Lens
- Row reduction exposes a **contradiction** if one exists: a row like `[0 0 ... 0 | c]` where `c ≠ 0`
- Reads as `0 = c` (false if c ≠ 0) → inconsistent
- No such row → consistent

### Rank Lens
- **Rank** = number of independent equations (pivot rows)
- For consistency: `rank(A) = rank([A | b])` where A is the coefficient matrix, b is the right-hand side
- If ranks differ, the system is inconsistent; if equal, it is consistent

**Key insight**: A system with proportional left-hand sides must have proportional right-hand sides to be consistent. Example: if row 2 = k × row 1 (in the coefficient part), then RHS₂ must equal k × RHS₁.

## Row Echelon Form (REF) — Checklist

A matrix is in **Row Echelon Form** if:

1. **All zero rows are at the bottom** — if any row is entirely zero, it is below all nonzero rows
2. **Leading entry rule** — the first nonzero entry (the *pivot*) in each row is **strictly to the right** of the pivot in the row above
3. **Zeros below pivots** — all entries directly below each pivot are zero

**When to stop here**:
- Checking consistency (look for contradiction rows)
- Identifying free vs dependent variables (from pivot positions)
- **Do NOT continue to RREF if** a contradiction row `[0 0 ... 0 | c]` with c ≠ 0 appears — system is already inconsistent

## Reduced Row Echelon Form (RREF) — Checklist

**RREF is REF plus additional constraints:**

1. ✓ Satisfies all REF requirements (leading entry rule, zeros below)
2. **Each pivot is 1** — normalize each pivot row by dividing by its pivot entry
3. **Each pivot is the ONLY nonzero in its column** — eliminate entries both *above and below* each pivot (unlike REF, which only clears below)

**When to use RREF**:
- Writing the general solution cleanly (preferred over back-substitution)
- Identifying free variables unambiguously
- **Do NOT push to RREF if** the system is inconsistent — REF is sufficient

**Key visual difference**:
```
REF: staircase pattern (zeros below)     RREF: isolated pivots (zeros above & below)
┌        ┐                               ┌        ┐
│ 1 * * │  pivot 1                      │ 1 * 0 │  pivot 1 isolated
│ 0 0 3 │  pivot 2                      │ 0 0 1 │  pivot 2 isolated
│ 0 0 0 │  all zeros                    │ 0 0 0 │  all zeros
└        ┘                               └        ┘
```

## Procedure: Row Reduction Algorithm

### Phase 1: Forward Elimination (to REF)

1. Identify the pivot column (leftmost nonzero in the current row or below)
2. Swap rows if needed so the pivot is in the current row
3. Scale the pivot row to make the pivot entry equal to 1 (optional but cleaner)
4. Eliminate all entries **below** the pivot (row operations: `R_i ← R_i - (entry / pivot) × R_pivot`)
5. Move to the next row and repeat until all rows processed

**Stop here to check consistency** — if `[0 0 ... 0 | c]` with c ≠ 0 appears, system is inconsistent.

### Phase 2: Back Substitution (to RREF, if system is consistent)

1. Start with the bottom nonzero row
2. Scale the pivot to 1 if not already
3. Eliminate all entries **above** the pivot (row operations: `R_i ← R_i - (entry) × R_pivot`)
4. Move to the next row up and repeat

**After this phase**: each pivot is isolated, and the solution is nearly readable.

## Extracting the General Solution from RREF

Given RREF with consistent system:

1. **Identify pivot vs free columns**
   - Pivot columns: columns containing a pivot (one per row)
   - Free columns: remaining columns (one free variable per free column)

2. **Assign parameters to free variables**
   - For each free variable x_j, let x_j = parameter (s, t, u, ...)

3. **Solve for dependent variables**
   - Rearrange each RREF equation to isolate the dependent variable on the left
   - Express it in terms of the free parameters and constants

4. **Write the general solution as a vector**
   ```
   x = x_p + s·v₁ + t·v₂ + ...
   
   where:
     x_p = particular solution (set all free variables to 0)
     v_i = direction vector for the i-th free variable (standard basis element in that free position)
   ```

5. **Sanity check**: plug a few values of s, t back in to verify they satisfy all RREF equations.

### Example Walkthrough

**RREF equations** (hypothetical):
```
x₁ - 2x₂ + (10/3)x₄ = 1
x₃ + (1/3)x₄ = 1
```

**Step 1**: Pivots in columns 1 and 3 → x₁, x₃ are dependent; x₂, x₄ are free.

**Step 2**: Let x₂ = s, x₄ = t.

**Step 3**: Solve:
- From equation 2: x₃ = 1 - (1/3)t
- From equation 1: x₁ = 1 + 2s - (10/3)t

**Step 4**: Write as vector:
```
[x₁]   [1]     [2]      [-10/3]
[x₂] = [0] + s [1]  + t [  0  ]
[x₃]   [1]     [0]      [-1/3]
[x₄]   [0]     [0]      [  1  ]
```

**Step 5**: Verify by substitution (plug in s=1, t=2 and check both equations).

## Translating Span Membership to a System

**Problem type**: "For what value(s) of h is y in Span{v₁, v₂, v₃}?"

**Translation**: y is in the span if and only if we can write:
$$y = c_1 v_1 + c_2 v_2 + c_3 v_3$$

for some scalars c₁, c₂, c₃. This is a **linear system** in the unknowns c_i:

1. Write the vector equation as a column vector equation
2. Expand to get system equations (one per coordinate)
3. Form the augmented matrix `[v₁ v₂ v₃ | y]` where the unknown h appears in the RHS
4. Row reduce to REF and check consistency
5. Consistency is independent of h only for specific value(s) of h; those are your answer

**Key insight**: The vectors v₁, v₂, v₃ become the *columns* of the coefficient matrix (not rows). The question asks: is there a coefficient vector c = [c₁, c₂, c₃]ᵀ such that [v₁ v₂ v₃] c = y?

## Common Pitfalls

- **Confusing REF and RREF**: REF has zeros *below* pivots; RREF has zeros *above and below*. Stop at REF to save work if you only need consistency.
- **Forgetting to check consistency before solving**: If you see `[0 0 ... 0 | c]` with c ≠ 0, stop immediately — the system is inconsistent and has no solution.
- **Misidentifying free variables**: Free variables correspond to *non-pivot columns*, not rows. A column with no pivot means that variable can be chosen freely.
- **Dropping zero rows during RREF**: Zero rows `[0 0 ... 0 | 0]` are harmless and should stay (they say 0 = 0, which is always true).
- **Wrong direction vectors**: Direction vectors are derived from *free column coefficients*, with a 1 in the row of the free variable itself (and a 0 in all other free variable positions).
- **Forgetting back-substitution**: If you only do forward elimination (REF), you can still read off free variables but solving for dependent variables requires rearranging each equation. RREF does this automatically.

## Three Problem Archetypes

All three use row reduction as the core technique but ask different questions:

| Problem | Goal | Method |
|---------|------|--------|
| **Consistency with parameters** | Find values of h, k that make the system consistent | Row reduce and require all RHS rows to be zero |
| **Solve and find general solution** | If consistent, describe *all* solutions | Row reduce to RREF, identify free variables, extract general solution vector |
| **Span membership** | For what h is vector y in Span{v₁, v₂, v₃}? | Translate to `[v₁ v₂ v₃ \| y]` system, row reduce, check consistency condition on h |