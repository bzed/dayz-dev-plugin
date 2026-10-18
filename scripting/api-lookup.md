# Looking Up DayZ APIs and Docs

Where to verify classes, methods, config tokens and server settings, and how to fetch them. Use this
whenever you are not 100% sure a class, method or token exists (see the No Hallucination Policy in SKILL.md).

## Bundled API index (use first)
The vanilla script API of the shipped build is in `api/dayz-api.txt.xz` (signatures only, no bodies, first line of
`//!` doc comments, modded parts merged, private members omitted). Query it with `scripts/dayz-api.py`
(Python 3 stdlib only; run it by its path inside the skill directory):
```bash
dayz-api.py class CarScript --inherited   # members of CarScript and every base class
dayz-api.py find 'UpdateLights' -c CarScript   # member lines matching a regex, optionally in one class
dayz-api.py find 'OnCEUpdate'             # across all classes (also enum values and top-level decls)
dayz-api.py sub Weapon_Base [--all]       # subclasses
dayz-api.py enum EStatLevels              # enum values
dayz-api.py src PlayerBase              # declaring script file(s), ready for armake2 cat
dayz-api.py chain PlayerBase              # PlayerBase > ManBase > DayZPlayerImplement > ...
```
Format: `CLASS Name<T> : Base @layers` (1=1_Core .. 5=5_Mission, layers that declare it; the index stores the declaring files, shown by `src`), then members as
`[static|protected|native] ret Name(params) #doc` or `type field`. Overrides are collapsed into one
`override: A B C` line (the signature is in the base class). `native` = engine-implemented (`proto native`).
A `#base differs under #ifdef: A or B` line means the base class depends on a define (for example `Transport` is `Pawn` or `EntityAI`); the site's `bases[].cond` names the define. Output is capped at 120 lines (`--max N`). The index covers vanilla only, not CF/Expansion/mods, and not method bodies
(for behavior use DayZ-Script-Diff below). Regenerate after a new build:
`python3 scripts/build-api-index.py <dayz-sources>/scripts api --build "<ver> build <n>"`.

## Extracting the real sources (when the index is not enough)
For one class, do not extract everything: `dayz-api.py src X` gives the declaring file(s), all inside
`<install>/dta/scripts.pbo`, and `armake2 cat <install>/dta/scripts.pbo '4_World\Entities\ItemBase.c'` prints that
file (**tested**, build 25956772). Use the full extraction below when you need many files or `grep` across the code.

Method bodies and non-vanilla code are not in the index. Extract them from the installed PBOs with
`scripts/extract-dayz-sources.sh <install-or-mod-dir> <out-dir>` (needs armake2 on PATH; put `<out-dir>` under
`/tmp` or `/var/tmp`). It reads only code, never models or textures: `*.c *.cpp *.h *.hpp *.inc *.json *.cfg *.txt`,
plus every `config.bin` derapified to `config.cpp`. Output follows the PBO prefix, so `scripts.pbo` becomes
`<out>/scripts/{1_Core..5_Mission}` and `Addons/ai.pbo` (prefix `DZ\AI`) becomes `<out>/DZ/AI/config.cpp`.
Takes about 90 s for the whole vanilla install (3.0k script files, 270 configs, 60 MB). **(tested)** build 25956772:
the extracted `scripts/*.c` were byte-identical to the reference source tree; only `config.cpp` formatting differs
(derapify layout).

Where the PBOs live (Steam on Linux; the install is `steamapps/common/DayZ`):
| What | Path |
|------|------|
| Script PBO (all `.c`) | `<install>/dta/scripts.pbo` (prefix `scripts`); `dta/bin.pbo`, `gui.pbo`, `system.pbo` hold more configs and layouts |
| Vanilla addon configs | `<install>/Addons/*.pbo` (one `config.bin` per PBO, prefix `DZ\...`) |
| DLC maps/content | `<install>/<dlc>/Addons/*.pbo`, e.g. `sakhal/Addons`, `nasdara/addons` (name case varies) |
| Workshop mods | `steamapps/workshop/content/221100/<workshop-id>/addons/*.pbo`; the `@xxxxxxxx` entries in the install dir are symlinks to them |
Do not follow the `@...` symlinks when scanning the install dir (the script uses `find` without `-L`, so mods are
skipped there). Extract a mod by passing its workshop folder instead. Encrypted `.ebo` files cannot be unpacked.
Single files without extracting: `armake2 inspect <pbo>` lists files, `armake2 cat <pbo> 'dir\file.c'` prints one
(backslash in the inner path). Installed armake2 0.3.0 has no `-x` on `unpack`, hence the per-file `cat`.
After extracting a new stable build, regenerate the index (see above).

## Verification Sources
| Type | Source | Action |
|------|--------|--------|
| Script API (latest build; `/v/experimental/` for the experimental build) | https://diff.yadz.app/ | `api/classes/<Name>.json` via curl/jq or WebFetch |
| Build diff / changelog | https://diff.yadz.app/changelog/ | API diff between any two builds (JS page - use Script Diff git for exact diffs) |
| Deprecated APIs | https://diff.yadz.app/deprecated/ | Everything marked `[Obsolete]` |
| Script Diff (official) | https://github.com/BohemiaInteractive/DayZ-Script-Diff | Check exact source code |
| Enforce Syntax | https://community.bistudio.com/wiki/DayZ:Enforce_Script_Syntax | Language reference |
| Config tokens | https://community.bistudio.com/wiki/CfgVehicles_Config_Reference | Config.cpp reference |
| Central Economy | https://github.com/BohemiaInteractive/DayZ-Central-Economy | types.xml, events.xml |
| CF docs | https://github.com/Arkensor/DayZ-CommunityFramework | CF source + docs |
| Expansion wiki | https://github.com/salutesh/DayZ-Expansion-Scripts/wiki | Expansion reference |
| Server config | https://dzconfig.com/wiki/ | Server XML/JSON configs |
| DeepWiki Expansion | https://deepwiki.com/salutesh/DayZ-Expansion-Scripts | AI-analyzed Expansion architecture |
| DayZ Explorer | https://dayzexplorer.zeroy.com/ | Enforce essentials, Math, FileIO, Widget API |

## Dynamic Fetching - Decision Tree

### Step 1: Classify the Request

| If user asks about... | Action |
|-----------------------|--------|
| Enforce Script class/method (EntityAI, PlayerBase, etc.) | **FETCH from DayZ Scripts API** |
| Config.cpp tokens (CfgVehicles, CfgWeapons) | **FETCH from BI Wiki** |
| Central Economy (types.xml, events.xml) | **FETCH from DayZ-Central-Economy repo** |
| CF feature (RPCManager, Modules, NetworkedVariables) | **FETCH from CF GitHub** |
| Expansion system (Market, Quests, AI, Basebuilding) | **FETCH from Expansion wiki** |
| Script diff between versions | **FETCH from DayZ-Script-Diff repo** |
| Server configuration | **FETCH from DZconfig wiki** |
| Mod structure, best practices | **READ local files** |
| 1.28 / 1.30 compatibility/changes | **READ local compatibility files** |

### Step 2: WebFetch URLs

#### Script API Reference (DIFF, latest PC stable)
**Base URL:** `https://diff.yadz.app/` (formerly `dayz-scripts.yadz.app`, which now redirects; the old
Doxygen paths like `/d5/d78/group___enforce` are gone)

The site publishes one JSON per type for agents (see https://diff.yadz.app/agent.md; `api.json` is now only a
name index, so jq queries on `.classes[]` no longer work):
| File | Content |
|------|---------|
| `https://diff.yadz.app/api/classes/<Name>.json` | One class: `base`, `bases` (with `cond` when the base depends on a define), `methods`, `members`, file and line. Names are case-sensitive; follow `base` for inherited members |
| `https://diff.yadz.app/api/enums/<Name>.json` | One enum |
| https://diff.yadz.app/api/globals.json | Functions, constants, typedefs, macros outside any class |
| https://diff.yadz.app/api.json | Name index of every class and enum (use when a name 404s) |
| https://diff.yadz.app/assets/notes.json | Community notes keyed by `Type` or `Type.Member` (not from BI) |
| https://diff.yadz.app/assets/versions.json | Every documented build with its DayZ-Script-Diff commit `sha` |

```bash
curl -s https://diff.yadz.app/api/classes/CarScript.json | jq '{name, base, file}'
curl -s https://diff.yadz.app/api/classes/CarScript.json | jq -c '.methods[] | select(.name=="UpdateLights")'
curl -s https://diff.yadz.app/assets/notes.json | jq '."ActionBase.ActionCondition"'
```
**(tested)** 2026-10-18, site build 1.30.164078. The site is latest-only; older builds are HTML under `/v/<build>/`.

**Key API Pages:**
| Category | URL |
|----------|-----|
| Enforce Essentials | https://diff.yadz.app/topics/Enforce/ |
| Math | https://diff.yadz.app/topics/Math/ |
| Widget UI System | https://diff.yadz.app/topics/Widget/ |
| Physics | https://diff.yadz.app/topics/Physics/ |
| Globals (functions, enums, constants) | https://diff.yadz.app/globals/ |
| Deprecated | https://diff.yadz.app/deprecated/ |
| Release notes (incl. MODDING sections) | https://diff.yadz.app/release-notes/ |
| Older builds (HTML) | `https://diff.yadz.app/v/<label>/` e.g. `/v/128u4/`, `/v/experimental/` |

#### Alternate API Reference (older but comprehensive)
**Base URL:** `https://dayzexplorer.zeroy.com/`

| Page | URL |
|------|-----|
| Enforce Core | https://dayzexplorer.zeroy.com/group___enforce.html |
| Math Functions | https://dayzexplorer.zeroy.com/group___math.html |
| FileIO API | https://dayzexplorer.zeroy.com/group___file.html |
| Particle Effects | https://dayzexplorer.zeroy.com/group___particle_effect.html |
| Widget API | https://dayzexplorer.zeroy.com/group___widget_a_p_i.html |
| DiagMenu | https://dayzexplorer.zeroy.com/group___diag_menu.html |
| Weather Class | https://dayzexplorer.zeroy.com/class_weather.html |
| Vector Class | https://dayzexplorer.zeroy.com/classvector.html |

#### Official Script Source (for exact implementations)
```
WebFetch(
  url: "https://github.com/BohemiaInteractive/DayZ-Script-Diff/tree/main/scripts",
  prompt: "Find the source code for '{CLASS_NAME}' in the DayZ script tree.
           Show the class definition, methods, and inheritance."
)
```

#### Config References
```
WebFetch(
  url: "https://community.bistudio.com/wiki/CfgVehicles_Config_Reference",
  prompt: "Find the config token '{TOKEN_NAME}' and its usage.
           Include: type, default value, parent class, example."
)
```

#### Central Economy
```
WebFetch(
  url: "https://github.com/BohemiaInteractive/DayZ-Central-Economy",
  prompt: "Find the economy configuration for '{ITEM_OR_SETTING}'.
           Include: types.xml entry, spawn parameters, nominal/min values."
)
```

#### Community Framework
```
WebFetch(
  url: "https://github.com/Arkensor/DayZ-CommunityFramework/tree/production/docs",
  prompt: "Find documentation for CF '{FEATURE}'.
           Include: API, usage examples, required setup."
)
```

#### Expansion Scripts
```
WebFetch(
  url: "https://github.com/salutesh/DayZ-Expansion-Scripts/wiki",
  prompt: "Find documentation for Expansion '{SYSTEM}'.
           Include: settings, configuration, scripting API."
)
```

#### Server Configuration
```
WebFetch(
  url: "https://dzconfig.com/wiki/",
  prompt: "Find documentation for '{CONFIG_FILE}'.
           Include: all parameters, types, default values, examples."
)
```
