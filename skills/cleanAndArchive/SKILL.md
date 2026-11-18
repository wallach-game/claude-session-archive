---
name: cleanAndArchive
description: Bulk clean-up of old Claude Code sessions. Asks how old (days/weeks/months), lists matching sessions, lets the user pick per session whether to keep, archive (zip + wipe) or delete. Use when the user types /cleanAndArchive or asks to clean up / archive / delete old sessions or chats.
---

# /cleanAndArchive

Uses the shared script `~/.claude/skills/archive/archive.ps1` (see the `archive` skill for commands). Run with `powershell -NoProfile -File <script> <cmd>`; output is JSON.

## Steps
1. **Age.** Ask the user (AskUserQuestion): "Sessions older than?" Options like 7 days / 30 days / 90 days (user can type "Other": days, weeks, months - convert to days).
2. **List.** `list -Days <N>`. Skip entries with `live:true` (never offered). Show a compact table sorted oldest first: `short id | modified | sizeMB | title | project`, plus total count and total MB. If 0 matches, say so and stop.
3. **Archive folder.** Run `config`; if `dest` is empty, ask where and `config -Dest`.
4. **Picker.** Default action for every session is KEEP. Ask the user how to decide, with the quickest paths first:
   - AskUserQuestion with "Archive all / Delete all / Keep all / Choose per session".
   - For "Choose per session", page through the sessions (max 4 questions x multiSelect per call): for each batch ask which to **archive** (multiSelect), then from the rest which to **delete** (multiSelect). Anything unselected is kept. Each option label = `<short id> <title>`, description = `<modified>, <sizeMB> MB`. For >20 sessions, first offer to filter (by project, by size > X MB) instead of paging everything.
5. **Confirm the plan** in one message: N archive (X MB -> zip), N delete (permanent, no copy), N keep. Wait for an explicit yes. Deletes are irreversible - call them out.
6. **Execute.**
   - Archive: `pack -Ids a,b,...` then, only for ids with `ok:true`, `wipe -Ids ...`. Failed packs are left untouched.
   - Delete: `delete -Ids ...`.
   - Report per-session failures (e.g. locked files) verbatim.
7. **Report:** archived count + zip folder + MB freed, deleted count, kept count, failures. Mention restore: `archive.ps1 restore -Zip "<zip>"`.

## Rules
- Never touch `live:true` sessions or the current session.
- Never wipe without a verified zip (the script refuses). Never delete anything the user did not explicitly select.
- Memory is archived into each zip as a snapshot but never removed from disk by these skills.
