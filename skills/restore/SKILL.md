---
name: restore
description: Restore an archived Claude Code session from the archive folder back into ~/.claude so it shows up in /resume again. Use when the user types /restore or asks to restore / bring back / unarchive a session or chat.
---

# /restore

Uses `~/.claude/skills/archive/archive.ps1` (run `powershell -NoProfile -File <script> <cmd>`; output is JSON).

## Steps
1. `config` -> if `dest` is empty, ask the user for the archive folder and `config -Dest "<path>"`.
2. `archives` -> lists zips (newest first) with `short, title, modified, sizeMB, onDisk`. If the user gave a search text or id with the command (`/restore <text>`), filter by title/id first. If none exist, say so and stop.
3. Pick: if exactly one match, confirm it; otherwise AskUserQuestion (max 4 options per question; for more, ask for a title keyword to narrow, or show the table and let the user type the short id). Option label = `<short> <title>`, description = `<modified>, <sizeMB> MB`. Allow multiSelect to restore several.
4. If `onDisk` is true, warn that the session already exists and restoring will overwrite its transcript with the archived version; ask to confirm.
5. For each chosen zip: `restore -Zip "<zip>"`.
6. Report: restored title + short id, and that it appears in `/resume` (restart Claude Code or reopen `/resume`; resume must be run from the same project folder it was created in - the project is `<project>` from the manifest/`list`). Mention the zip is kept; offer to delete it only if the user asks.

## Rules
- Existing memory files are never overwritten by restore (the script skips them).
- Archives are private; do not upload or share them.
