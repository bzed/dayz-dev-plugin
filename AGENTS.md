# Repository rules for agents

## Branches (remote `bzed`)

| Branch | Documents | Rule |
|---|---|---|
| `dayz-1.29` | DayZ 1.29 stable as it was | Frozen. Do not merge, push or edit it; it is the reference for how 1.29 looks. |
| `dayz-1.30` | DayZ 1.30 and migrating to it | Branch for 1.30 work and the 1.29 -> 1.30 migration. |
| `main` | The latest DayZ **experimental** release | Always tracks the newest experimental build; currently 1.30. |

- Commit new work on `main` unless told otherwise; only touch `dayz-1.30` when asked.
- Never push to `origin` (upstream DayZGhost); push to `bzed`.
- When a new experimental build (e.g. 1.31) arrives, `main` moves to it. Ask before creating or renaming version branches.

## Content rules

- Statements about game behavior need a test on a real server (see `testing/local-server.md`); mark them **(tested)** with the build number.
- `SKILL.md` frontmatter must be strict YAML (validate with `yaml.safe_load`) and the description must stay under 1024 characters.
- Keep `compatibility/YOURMOD_FindFilePath.c` behaviorally identical to CF-Test's `CF.FindFileEx`/`CF.ResolvePath`; re-diff it after each CF-Test update.
