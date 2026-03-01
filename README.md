# Handoff

Preserve and restore context between Claude Code sessions.

## The Problem

When working with Claude Code across multiple sessions, switching agents, or hitting context limits (auto-compaction), valuable context is lost:
- What task was being worked on
- Key decisions and their rationale
- Blockers and open questions
- Next steps to continue

## The Solution

Handoff captures "necessary and sufficient" context to a `docs/handoff/HANDOFF.md` file, enabling seamless continuation across sessions.

## Installation

```bash
# Add the marketplace
/plugin marketplace add thepushkarp/handoff

# Install the plugin
/plugin install handoff@handoff
```

## Commands

### `/handoff:create`

Capture current session context to `docs/handoff/HANDOFF.md`.

**What it captures:**
- Current task state (what's in progress)
- Key decisions and rationale
- Modified files
- Blockers and open questions
- Next steps
- Critical context (gotchas, patterns, etc.)
- Model summary (8–12 bullets)
- Handoff context (pasteable resume instructions)

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

The plugin includes always-on hooks that make compaction safe:

- **Before compaction** (`PreCompact`): appends a new entry to `docs/handoff/HANDOFF.md` with deterministic snapshot data and placeholders for a model-written summary/context.
- **After compaction** (`SessionStart` matcher `compact`): auto-injects the latest handoff entry back into Claude's context (stdout injection).
- **Enforcement** (`Stop`): if the latest entry still has TODO placeholders for **Model Summary** and **Handoff Context**, Claude is blocked from stopping (up to 3 attempts) until it fills them in.

This ensures you never lose important context to auto-compaction.

> Note: These scripts use `jq` when available to parse hook input and transcripts. Without `jq`, the plugin degrades gracefully but will capture less detail.

## Handoff File Format

Handoffs are stored in `docs/handoff/HANDOFF.md` with timestamped entries:

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

### Model Summary
- Login flow is complete; password reset in progress
- Using JWT sessions for stateless scaling
- Blocker: decide reset token expiry (1h vs 24h)

### Handoff Context (paste into next session)
1. Open `docs/handoff/HANDOFF.md` and focus on the most recent entry.
2. Implement password reset endpoint and tests first.
3. Confirm `AUTH_SECRET` is set before running tests.

---
```

## Use Cases

1. **Ending a session**: Run `/handoff:create` before closing Claude Code
2. **Switching contexts**: Create a handoff before switching to a different task
3. **Context limits**: Compaction auto-saves and re-injects a handoff entry
4. **Team handoffs**: Share `docs/handoff/HANDOFF.md` for async collaboration
5. **Resuming work**: Run `/handoff:resume` when starting a new session

## Tips

- **Be explicit about blockers**: Include specific questions or decisions needed
- **Include file paths**: Helps the next session navigate quickly
- **Note gotchas**: Things that weren't obvious save time later
- **Use auto mode carefully**: Good for continuing known tasks, but review mode helps verify context is correct

## Optional: Compaction instructions in CLAUDE.md

Claude Code supports project-level compaction guidance via a `CLAUDE.md` section named `# Compact instructions`:

```markdown
# Compact instructions

When compacting, preserve:
- the latest handoff entry in docs/handoff/HANDOFF.md
- current task state, blockers, and next steps
- key decisions and constraints
```

## Plugin maintenance notes

Claude Code caches plugin content by version. When you change plugin code, bump the version in `plugins/handoff/.claude-plugin/plugin.json` so existing users receive the update.

Useful commands when developing:

```bash
# Validate manifests and marketplace structure
/plugin validate

# If testing a local plugin directory (see Claude Code docs for the exact flag usage)
claude --plugin-dir ./plugins/handoff
```

## License

MIT
