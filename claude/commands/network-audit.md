---
description: Monitor network traffic, page weight, and API health using Playwright.
argument-hint: [url]
allowed-tools: [mcp__playwright__navigate, mcp__playwright__hover, Bash]
---

**Purpose:**
Analyze the network layer of a live URL to identify performance bottlenecks and hidden 4xx/5xx errors.

**Input:**
- **Target URL**: $ARGUMENTS
- **Thresholds**: 2MB Page Weight / 0 Failed Requests

**Workflow:**
1. **Navigation**: Use `mcp__playwright__navigate` to load $ARGUMENTS.
2. **Analysis Step**:
   * Inspect the network logs for all triggered API requests.
   * Calculate total transferred bytes to determine page weight.
   * **Important**: Specifically flag any requests returning status codes >= 400.
3. **Execution**:
   * Identify the slowest 3 assets (images, scripts, or XHR).
   * Verify if compression (gzip/brotli) is active on text assets.

**Output:**
**Report Step**: Provide a "Network Health Report" including total request count, total page size, and a list of all failing background requests.
