# Repository rules for agents

## Branches (remote `bzed`)

| Branch | Documents | Rule |
|---|---|---|
| `dayz-1.29` | DayZ 1.29 stable as it was | Frozen. Do not merge, push or edit it; it is the reference for how 1.29 looks. |
| `dayz-1.30` | DayZ 1.30 and migrating to it | Branch for 1.30 work and the 1.29 -> 1.30 migration. |
| `main` | The latest DayZ **stable** release | Tracks the current stable build; currently 1.30 (stable since Oct 15, 2026). |

- Commit new work on `main` unless told otherwise; only touch `dayz-1.30` when asked.
- Never push to `origin` (upstream DayZGhost); push to `bzed`.
- When the next version (e.g. 1.31) reaches stable, `main` moves to it. Ask before creating or renaming version branches, and before documenting an experimental build on `main`.

## Content rules

- Statements about game behavior need a test on a real server (see `testing/local-server.md`); mark them **(tested)** with the build number.
- `SKILL.md` frontmatter must be strict YAML (validate with `yaml.safe_load`) and the description must stay under 1024 characters.
- Keep `compatibility/YOURMOD_FindFilePath.c` behaviorally identical to CF's `CF.FindFileEx`/`CF.ResolvePath` (CF 1.5.9+); re-diff it after each CF update.
- Regenerate `api/dayz-api.txt.xz` with `scripts/build-api-index.py` from the vanilla scripts of each new stable build and keep the build number in its header current.
