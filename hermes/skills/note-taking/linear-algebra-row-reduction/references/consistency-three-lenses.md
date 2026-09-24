# Understanding Consistency: Geometric, Algebraic, Rank Perspectives

## Problem 1: When is 2×2 System Consistent?

**System**:
```
2x₁ - x₂ = h
-6x₁ + 3x₂ = k
```

### Geometric Lens
- Equation 1 is a line in 2D
- Equation 2 is another line in 2D
- **Consistent**: lines intersect (one point) or coincide (infinitely many)
- **Inconsistent**: lines are parallel and never meet

Notice: the second equation's left side is `-3 × (2x₁ - x₂)`, so both equations describe lines with the **same slope** (they are parallel or identical).

For them to describe the same line (not just parallel lines):
- Right side must also scale by -3: `k = -3h`
- If `k ≠ -3h`: parallel, distinct lines → **inconsistent**
- If `k = -3h`: same line → **infinitely many solutions, consistent**

### Algebraic Lens (Row Reduction)

**Augmented matrix**:
```
[  2  -1 | h   ]
[ -6   3 | k   ]
```

After R₂ ← R₂ + 3R₁:
```
[  2  -1 | h     ]
[  0   0 | k+3h  ]
```

**Consistency check**:
- Row 2 reads: `0 = k + 3h`
- If k + 3h ≠ 0 → contradiction → **inconsistent**
- If k + 3h = 0 (i.e., k = -3h) → true statement → **consistent**

### Rank Lens

Coefficient matrix A:
```
[  2  -1 ]
[ -6   3 ]
```

Rank(A) = 1 (because row 2 = -3 × row 1, they are linearly dependent)

Augmented matrix [A | b]:
```
[  2  -1 | h   ]
[ -6   3 | k   ]
```

For consistency: Rank(A) = Rank([A | b])

Both have rank 1 ⟺ the augmented column b is in the column space of A ⟺ the b vector is a scalar multiple of any column of A ⟺ the two rows of [A | b] are proportional ⟺ k = -3h.

## Conclusion

All three lenses converge on the same answer: **h and k are consistent if and only if k = -3h**.

The **key insight** is recognizing when left-hand sides are proportional — that forces a constraint on the right-hand sides.
