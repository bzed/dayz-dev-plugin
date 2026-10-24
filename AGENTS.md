# Repository rules for agents

## Branches (remote `origin` = github.com/bzed/dayz-dev-plugin)

| Branch | Documents | Rule |
|---|---|---|
| `dayz-1.29` | DayZ 1.29 stable as it was | Frozen. Do not merge, push or edit it; it is the reference for how 1.29 looks. |
| `dayz-1.30` | DayZ 1.30 and migrating to it | Branch for 1.30 work and the 1.29 -> 1.30 migration. |
| `main` | The latest DayZ **stable** release | Tracks the current stable build; currently 1.30 (stable since Oct 15, 2026). |

- Commit new work on `main` unless told otherwise; only touch `dayz-1.30` when asked.
- The upstream DayZGhost repo is not configured as a remote; never push there.
- When the next version (e.g. 1.31) reaches stable, `main` moves to it. Ask before creating or renaming version branches, and before documenting an experimental build on `main`.

## Content rules

- Statements about game behavior need a test on a real server (see `testing/local-server.md`); mark them **(tested)** with the build number.
- `SKILL.md` frontmatter must be strict YAML (validate with `yaml.safe_load`) and the description must stay under 1024 characters.
- `compatibility/YOURMOD_FindFilePath.c` is obsolete since DayZ 1.30.164200 (`FindFile` fixed) and frozen at the CF 1.5.9 `ResolvePath` behavior of early October 2026; it is no longer kept in sync with later CF updates.
- Regenerate `api/dayz-api.txt.xz` with `scripts/build-api-index.py` from the vanilla scripts of each new stable build and keep the build number in its header current.
- Regenerate `api/mod-{expansion,cf,cot,dabs}.txt.xz` (`build-api-index.py <extract-dir> api --mod NAME --build "<name> <version> (workshop <id>, updated <date>)"`) after each update of those Workshop mods. Always unpack fresh into a new `/tmp` dir with `scripts/extract-dayz-sources.sh <workshop dir> <out>` (never reuse an old unpack). Expansion = Workshop 2572331007 (DayZ-Expansion-Bundle), CF 1559212036, COT 1564026768 (not the `-Test` mod), Dabs 2545327648; the separate DayZ-Expansion-Licensed mod is not indexed.
