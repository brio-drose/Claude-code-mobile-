# Claude-code-mobile-

Claude Code skill for Gmail inbox management — read threads, triage unread mail, and draft responses without leaving the terminal.

## Skills

### `/inbox-manager`

Manage your Gmail inbox from Claude Code.

**Usage:**

| Command | Action |
|---|---|
| `/inbox-manager` | Show 10 most recent unread inbox threads |
| `/inbox-manager search <query>` | Search threads (natural language or Gmail syntax) |
| `/inbox-manager read <thread_id>` | Read a full thread |
| `/inbox-manager draft <thread_id>` | Draft a reply to a thread |
| `/inbox-manager draft new <to> <subject>` | Draft a new outbound email |
| `/inbox-manager triage` | Walk through unread threads and apply label/archive actions |

**What it does:**
- Fetches unread inbox threads and presents them as a numbered list
- Reads full thread content including all messages in a conversation
- Drafts contextually appropriate replies that match the email's tone
- Saves approved drafts to Gmail (never sends automatically — you always review first)
- Supports triage mode to quickly label or archive batches of email

**Requirements:**
- Gmail MCP server must be connected (the `mcp__f9f8d230...` Gmail tools)

## Setup

This skill is a Claude Code custom slash command. Place the `.claude/commands/` directory in your project root and Claude Code will automatically register `/inbox-manager`.
