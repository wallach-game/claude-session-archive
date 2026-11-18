---
name: archive
description: Archive the CURRENT Claude Code session to a zip (transcript, readable transcript.md, subagent/tool data, file-history, session-env, debug log, project memory), verify it, then wipe the session from ~/.claude. Use when the user types /archive or says "archive this session / archivuj vlakno". Also hosts the shared script used by /cleanAndArchive.
---

# /archive

Script: `~/.claude/skills/archive/archive.ps1` (PowerShell; run `powershell -NoProfile -File <script> <cmd> ...`; all output is JSON). Commands: `config`, `list`, `pack`, `wipe`, `wipe-later`, `delete`, `restore`.

## Steps
1. **Archive folder.** Run `config`. If `dest` is empty/null, ASK the user where to store archives (suggest `C:\Users\<user>\Documents\claude-archive`), then `config -Dest "<path>"`. Never guess it; only ask the first time.
2. **Current session id** = `$env:CLAUDE_CODE_SESSION_ID`. If empty, run `list` and pick the most recent one, confirming with the user.
3. **Pack:** `pack -Ids <id>` (add `-NoMemory` only if the user asks). It verifies the zip (every entry present, sizes equal) before reporting `ok:true`. If `ok` is false, stop and report - delete nothing.
4. **Tell the user** the zip path and size. Before wiping, state clearly that the session will disappear from /resume and ask for confirmation unless the user already said to wipe.
5. **Wipe the current session:** a live session cannot be deleted while running, so run `wipe-later -Ids <id>`. It starts a hidden process that waits for this Claude process to exit, then deletes the session files (refuses if no archive zip exists). Tell the user to exit Claude (`/exit`) now; log is `~/.claude/skills/archive/wipe-later.log`.
6. Final report: zip path, what was included (`files` count), that wipe is scheduled for exit, and how to restore: `archive.ps1 restore -Zip "<zip>"` (puts files back at original paths, never overwrites existing memory files).

## Rules
- Never delete before a verified `pack` for that id (the script enforces it for `wipe`; `delete` skips it and is only for /cleanAndArchive's explicit delete choice).
- Archive content is private (transcripts, memory). Do not upload or share it.
