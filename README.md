# Handoff

Preserve and restore context between Claude Code sessions.

## The Problem

When working with Claude Code across multiple sessions, switching agents, or hitting context limits (auto-compaction), valuable context is lost:
- What task was being worked on
- Key decisions and their rationale
- Blockers and open questions
- Next steps to continue

## The Solution

Handoff captures "necessary and sufficient" context to a `.claude/HANDOFF.md` file, enabling seamless continuation across sessions.

## Installation

```bash
# Add the marketplace
/plugin marketplace add thepushkarp/handoff

# Install the plugin
/plugin install handoff@handoff
```

## Commands

### `/handoff:create`

Capture current session context to `.claude/HANDOFF.md`.

**What it captures:**
- Current task state (what's in progress)
- Key decisions and rationale
- Modified files
- Blockers and open questions
- Next steps
- Critical context (gotchas, patterns, etc.)

**Usage:**
```
/handoff:create
```

The handoff is **appended with a timestamp**, creating a history log.

### `/handoff:resume`

Load existing handoff context to continue work.

**Default mode:** Displays handoff summary and asks how to proceed.
```
/handoff:resume
```

**Auto mode:** Automatically loads context and starts working on next steps.
```
/handoff:resume --auto
```

## Automatic Handoff Prompt

The plugin includes a `PreCompact` hook that **prompts you before context compaction**:

> "Context is about to be compacted. Would you like me to create a handoff first to preserve important context? (yes/no)"

This ensures you never lose important context to auto-compaction.

## Handoff File Format

Handoffs are stored in `.claude/HANDOFF.md` with timestamped entries:

```markdown
---

## Handoff: 2025-01-05 14:32:00

### Current Task State
Implementing user authentication feature. Login flow is complete, working on password reset.

### Key Decisions
- Using JWT for session tokens: Better for stateless scaling
- Email verification required: Security requirement from product

### Modified Files
- `src/auth/login.ts` - Added JWT generation
- `src/auth/middleware.ts` - Token validation middleware
- `tests/auth.test.ts` - Login flow tests

### Blockers / Open Questions
- Need to decide on password reset token expiry (1hr vs 24hr?)

### Next Steps
1. Implement password reset endpoint
2. Add email sending for reset tokens
3. Write tests for reset flow

### Critical Context
- The `AUTH_SECRET` env var must be set or tests fail silently
- Rate limiting is handled in nginx, not in code

---
```

## Use Cases

1. **Ending a session**: Run `/handoff:create` before closing Claude Code
2. **Switching contexts**: Create a handoff before switching to a different task
3. **Context limits**: The PreCompact hook reminds you before auto-compaction
4. **Team handoffs**: Share `.claude/HANDOFF.md` for async collaboration
5. **Resuming work**: Run `/handoff:resume` when starting a new session

## Tips

- **Be explicit about blockers**: Include specific questions or decisions needed
- **Include file paths**: Helps the next session navigate quickly
- **Note gotchas**: Things that weren't obvious save time later
- **Use auto mode carefully**: Good for continuing known tasks, but review mode helps verify context is correct

## License

MIT
