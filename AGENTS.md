# Repository rules for agents

## Branches (remote `origin` = github.com/bzed/dayz-dev-plugin)

| Branch | Documents | Rule |
|---|---|---|
| `dayz-1.29` | DayZ 1.29 stable as it was | Frozen. Do not merge, push or edit it; it is the reference for how 1.29 looks. |
| `dayz-1.30` | DayZ 1.30 and migrating to it | Branch for 1.30 work and the 1.29 -> 1.30 migration. |
| `main` | The latest DayZ **stable** release | Tracks the current stable build; currently 1.30 (stable since Oct 15, 2026). |

- Commit new work on `main` unless told otherwise; only touch `dayz-1.30` when asked.
- Push to `origin` only.
- When the next version (e.g. 1.31) reaches stable, `main` moves to it. Ask before creating or renaming version branches, and before documenting an experimental build on `main`.

## Content rules

- Statements about game behavior need a test on a real server (see `testing/local-server.md`); mark them **(tested)** with the build number.
- `SKILL.md` frontmatter must be strict YAML (validate with `yaml.safe_load`) and the description must stay under 1024 characters.
- `compatibility/YOURMOD_FindFilePath.c` is obsolete since DayZ 1.30.164200 (`FindFile` fixed) and frozen at the CF 1.5.9 `ResolvePath` behavior of early October 2026; it is no longer kept in sync with later CF updates.
- Regenerate `api/dayz-api.txt.xz` with `scripts/build-api-index.py` from the vanilla scripts of each new stable build and keep the build number in its header current.
- Regenerate `api/mod-{expansion,cf,cot,dabs}.txt.xz` (`build-api-index.py <extract-dir> api --mod NAME --build "<name> <version> (workshop <id>, updated <date>)"`) after each update of those Workshop mods. Always unpack fresh into a new `/tmp` dir with `scripts/extract-dayz-sources.sh <workshop dir> <out>` (never reuse an old unpack). Expansion = Workshop 2572331007 (DayZ-Expansion-Bundle), CF 1559212036, COT 1564026768 (not the `-Test` mod), Dabs 2545327648; the separate DayZ-Expansion-Licensed mod is not indexed.

## Releases

Semver. Major for a new DayZ stable target or breaking layout changes, minor for new features or content, patch for fixes and doc corrections. Release from `main` only.

The version lives in four places that must match: `package.json`, `.claude-plugin/plugin.json`, and `.claude-plugin/marketplace.json` (`metadata.version` and `plugins[0].version`). Check with `grep -rn '"version"' package.json .claude-plugin/`.

Steps:

1. Make sure the tree is clean, `main` is up to date with `origin`, and the API indexes and docs are current for the stable build (see Content rules).
2. Bump the version in all four places, e.g. `sed -i 's/"version": "OLD"/"version": "NEW"/' package.json .claude-plugin/plugin.json .claude-plugin/marketplace.json`.
3. Run `claude plugin validate .`; it must pass without warnings.
4. Commit as `Release X.Y.Z` (with the usual Co-Authored-By trailer).
5. Tag it: `git tag -a vX.Y.Z -m "dayz-dev X.Y.Z: <one-line summary>"`.
6. Push both: `git push origin main vX.Y.Z`.
7. Optional: `gh release create vX.Y.Z --generate-notes`.
8. Merge to `dayz-1.30` (fast-forward) only when asked, then push it too.
