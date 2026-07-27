---
description: Compare local UI state against a production "Gold Standard".
argument-hint: [local_url] [prod_url]
allowed-tools: [mcp__playwright__navigate, mcp__playwright__screenshot, Bash]
---

**Purpose:**
Detect visual drift and layout shifts between the local development environment and the production baseline.

**Input:**
- **Local Target**: $1
- **Prod Baseline**: $2
- **Storage**: ./test-results/screenshots/

**Workflow:**
1. **Baseline Capture**:
   * Navigate to $2 (Production).
   * Save a screenshot to `{{storage}}baseline.png`.
2. **Current State Capture**:
   * Navigate to $1 (Local).
   * Save a screenshot to `{{storage}}current.png`.
3. **Loop Step** (LIMIT TO 3 LOOPS):
   <loop>
   * Compare pixel data between `baseline.png` and `current.png`.
   * If a visual difference > 5% is detected, flag the component for review.
   * Repeat for Mobile (375px) and Desktop (1440px) resolutions.
   </loop>

**Output:**
**Report**: Provide a "Visual Diff Summary" indicating if the layouts match and the file paths for the side-by-side comparison images.
