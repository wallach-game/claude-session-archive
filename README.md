# claude-session-archive

Two [Claude Code](https://claude.com/claude-code) skills for managing old sessions (Windows / PowerShell).

| Skill | Command | What it does |
|---|---|---|
| `archive` | `/archive` | Zips the current session (transcript, readable `transcript.md`, subagent/tool data, file history, debug log, project memory), verifies the zip, then wipes the session from `~/.claude` on exit. |
| `cleanAndArchive` | `/cleanAndArchive` | Bulk clean-up: asks how old, lists matching sessions, and lets you keep, archive (zip + wipe) or delete each one. |

`cleanAndArchive` reuses `skills/archive/archive.ps1`, so install both.

## Install

Copy the folders into your user skills directory:

```powershell
git clone https://github.com/wallach-game/claude-session-archive
Copy-Item -Recurse claude-session-archive\skills\* $HOME\.claude\skills\
```

Restart Claude Code. On first use the skill asks where to store archives and saves it to `skills/archive/config.json`.

## Layout

```
skills/
  archive/
    SKILL.md        # frontmatter (name, description) + instructions
    archive.ps1     # commands: config, list, pack, wipe, wipe-later, delete, restore
    config.json     # archive destination (empty by default)
  cleanAndArchive/
    SKILL.md
```

## Restore

```powershell
powershell -NoProfile -File $HOME\.claude\skills\archive\archive.ps1 restore -Zip "<path to zip>"
```

Archives contain private transcripts and memory - don't share them.

## License
MIT
