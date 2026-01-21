---
description: Capture current session context to docs/handoff/HANDOFF.md
allowed-tools: Read, Write, Edit, Bash(git:*), Bash(mkdir:*)
---

Create a comprehensive handoff document to preserve context for future Claude sessions.

## Steps

1. **Analyze Session Context**
   Review the current conversation and gather:

   - **Current Task State**: What is currently being worked on? What's in progress?
   - **Key Decisions**: Important architectural or implementation choices made and their rationale
   - **Modified Files**: Files that were changed during this session (check git log and git status if available, or recall from conversation)
   - **Blockers/Open Questions**: Anything unresolved or blocking progress
   - **Next Steps**: Clear, actionable items for the next session to continue
   - **Critical Context**: Gotchas, edge cases discovered, important patterns, or anything the next session absolutely needs to know

2. **Check Git Log and Status** (if in a git repo)
   Run `git log --oneline --decorate --all --graph` and `git status` to identify modified files.

3. **Read Existing Handoff** (if any)
   Try to read docs/handoff/HANDOFF.md to check if it exists. If it does, you'll append to it.

4. **Create Directory and Append Handoff**
   Ensure docs/handoff/ directory exists with `mkdir -p docs/handoff`, then append a new timestamped entry to docs/handoff/HANDOFF.md:

   ```markdown
   ---

   ## Handoff: [TIMESTAMP]

   ### Current Task State
   [What was being worked on, current status]

   ### Key Decisions
   - [Decision 1]: [Rationale]
   - [Decision 2]: [Rationale]

   ### Modified Files
   - `path/to/file1.ts` - [brief description of changes]
   - `path/to/file2.py` - [brief description of changes]

   ### Blockers / Open Questions
   - [Any unresolved issues or questions]

   ### Next Steps
   1. [First actionable item]
   2. [Second actionable item]
   3. [Third actionable item]

   ### Critical Context
   [Important gotchas, patterns, or context the next session needs]

   ---
   ```

5. **Confirm Handoff Created**
   After writing, confirm the handoff was appended successfully and summarize what was captured.

## Important Notes

- Be comprehensive but concise - capture what's necessary and sufficient
- Focus on information that would be lost during context compaction
- Include specific file paths, function names, and line numbers where relevant
- Prioritize actionable next steps over general observations
- If git is available, include recent commit hashes or branch info
