---
description: Scrape and update AI documentation using Firecrawl.
argument-hint: [url]
allowed-tools: [mcp__firecrawl__scrape, Bash]
---

**Purpose:**
Refresh the local AI knowledge base by purging stale data and scraping current docs.

**Input:**
- **Source URL**: $ARGUMENTS
- **Storage Path**: ./docs/ai/

**Workflow:**
1. **Purge**: Delete all existing files in `./docs/ai/` via Bash.
2. **Scrape Step**:
   * Use `mcp__firecrawl__scrape` to fetch the content of $ARGUMENTS in markdown format.
3. **Indexing**: 
   * Write the output to a new markdown file in the storage path.
   * **Important**: Ensure the filename is slugified based on the page title.

**Output:**
**Report Step**: Confirm the document update and provide the new file path.
