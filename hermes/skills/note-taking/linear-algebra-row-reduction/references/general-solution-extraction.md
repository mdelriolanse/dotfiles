# Extracting General Solution: Step-by-Step Walkthrough

## Starting Point: RREF Equations

After reducing a consistent system to RREF, you have equations like:

```
x₁ - 2x₂ + (10/3)x₄ = 1     ... (1)
x₃ + (1/3)x₄ = 1             ... (2)
```

Note: No equation for x₄, and x₂ doesn't appear as a leading term in any row. These are the **free variables**.

## Step 1: Identify Pivot vs Free Columns

Look at the RREF coefficient matrix (ignore the augmented column for now):

```
[  1  -2   0  10/3 ]
[  0   0   1   1/3 ]
```

- **Pivot columns**: 1 (leading 1 in row 1) and 3 (leading 1 in row 2)
  - These correspond to **dependent variables** x₁ and x₃
- **Non-pivot columns**: 2 and 4
  - These correspond to **free variables** x₂ and x₄

## Step 2: Assign Parameters to Free Variables

For each free variable, introduce a parameter (usually s, t, u, v, ...):

```
Let x₂ = s  (arbitrary real number)
Let x₄ = t  (arbitrary real number)
```

## Step 3: Solve for Dependent Variables

Rearrange each RREF equation to isolate the dependent variable:

**From equation (2)**:
```
x₃ + (1/3)x₄ = 1
x₃ + (1/3)t = 1    (substitute x₄ = t)
x₃ = 1 - (1/3)t    ← dependent variable in terms of free parameter
```

**From equation (1)**:
```
x₁ - 2x₂ + (10/3)x₄ = 1
x₁ - 2s + (10/3)t = 1    (substitute x₂ = s, x₄ = t)
x₁ = 1 + 2s - (10/3)t    ← dependent variable in terms of free parameters
```

## Step 4: Write as a Column Vector

Collect all variables into one vector:

```
⎡ x₁ ⎤   ⎡ 1 + 2s - (10/3)t ⎤
⎢ x₂ ⎥ = ⎢ s                 ⎥
⎢ x₃ ⎥   ⎢ 1 - (1/3)t       ⎥
⎣ x₄ ⎦   ⎣ t                 ⎦
```

## Step 5: Factor into Parametric Vector Form

Rewrite each component as: (constant) + s(coefficient of s) + t(coefficient of t)

```
x₁ = 1 + 2s - (10/3)t   =  1 + s(2) + t(-10/3)
x₂ = s                  =  0 + s(1) + t(0)
x₃ = 1 - (1/3)t        =  1 + s(0) + t(-1/3)
x₄ = t                  =  0 + s(0) + t(1)
```

Now extract the vectors:

```
⎡ x₁ ⎤   ⎡ 1 ⎤     ⎡ 2 ⎤     ⎡ -10/3 ⎤
⎢ x₂ ⎥ = ⎢ 0 ⎥ + s ⎢ 1 ⎥ + t ⎢  0   ⎥
⎢ x₃ ⎥   ⎢ 1 ⎥     ⎢ 0 ⎥     ⎢ -1/3 ⎥
⎣ x₄ ⎦   ⎣ 0 ⎦     ⎣ 0 ⎦     ⎣  1   ⎦
          ↑           ↑           ↑
      particular    direction   direction
      solution      vector 1    vector 2
      (x_p)         (v₁)        (v₂)
```

## Step 6: Write the Final Answer

$$x = x_p + s \cdot v_1 + t \cdot v_2$$

where:
- **x_p** = [1, 0, 1, 0]ᵀ (the particular solution, obtained by setting s=0, t=0)
- **v₁** = [2, 1, 0, 0]ᵀ (direction when free variable x₂ varies)
- **v₂** = [-10/3, 0, -1/3, 1]ᵀ (direction when free variable x₄ varies)
- **s, t ∈ ℝ** (arbitrary scalars; varying them traces out the solution set)

## Step 7: Verify (Sanity Check)

Plug in a test value, say s=1, t=2:

```
x = [1, 0, 1, 0]ᵀ + 1·[2, 1, 0, 0]ᵀ + 2·[-10/3, 0, -1/3, 1]ᵀ
  = [1+2-20/3, 0+1+0, 1+0-2/3, 0+0+2]ᵀ
  = [-5/3, 1, 1/3, 2]ᵀ
```

Check equation (1): x₁ - 2x₂ + (10/3)x₄ = -5/3 - 2(1) + (10/3)(2) = -5/3 - 2 + 20/3 = 15/3 - 2 = 5 - 2 = 1 ✓

Check equation (2): x₃ + (1/3)x₄ = 1/3 + (1/3)(2) = 1/3 + 2/3 = 1 ✓

Both equations are satisfied! ✓

## The Parametric Form Interpretation

The solution set is a **2-dimensional affine subspace** (a plane) in 4D space:
- **x_p** is one point on the plane
- **v₁ and v₂** are two independent direction vectors spanning the plane
- By varying **s** and **t** independently over all real numbers, we trace out every point on the plane

This is the complete solution set.
