---
description: Load existing handoff context to continue work
argument-hint: [--auto]
allowed-tools: Read, TodoWrite
---

Resume work from an existing handoff document at docs/handoff/HANDOFF.md.

## Behavior

**Default mode** (no arguments): Display the handoff content and ask the user how they want to proceed.

**Auto mode** (`--auto` flag): Automatically inject the context and begin working on the next steps.

## Steps

1. **Check for Handoff File**
   Read docs/handoff/HANDOFF.md if it exists.

2. **Parse Most Recent Handoff**
   The file may contain multiple handoff entries (appended with timestamps). Focus on the **most recent** handoff entry (the last `## Handoff: [TIMESTAMP]` section in the file).

3. **Based on Mode**:

   **If no arguments (default mode)**:
   - Display a summary of the most recent handoff:
     - When it was created
     - Current task state
     - Key decisions made
     - Any blockers
     - Next steps listed
   - Ask the user: "How would you like to proceed? I can:
     1. Start working on the next steps
     2. Review the full handoff details first
     3. Do something else - please specify"

   **If `--auto` flag provided**:
   - Silently load the context
   - Set up todos from the "Next Steps" section using TodoWrite
   - Begin working on the first next step immediately
   - Inform the user: "Resuming from handoff created at [TIMESTAMP]. Starting work on: [first next step]"

4. **Handle Missing Handoff**
   If docs/handoff/HANDOFF.md doesn't exist:
   - Inform the user: "No handoff file found at docs/handoff/HANDOFF.md. Would you like to describe your current task so I can help you continue?"

## Important Notes

- Pay attention to the "Critical Context" section - it contains gotchas and important info
- Respect any blockers mentioned - ask about their status before proceeding
- The "Key Decisions" section contains rationale that should guide continued work
- If multiple handoffs exist, you can offer to show history if user asks
