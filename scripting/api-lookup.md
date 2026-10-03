# Looking Up DayZ APIs and Docs

Where to verify classes, methods, config tokens and server settings, and how to fetch them. Use this
whenever you are not 100% sure a class, method or token exists (see the No Hallucination Policy in SKILL.md).

## Verification Sources
| Type | Source | Action |
|------|--------|--------|
| Script API (latest stable, 1.29; `/v/experimental/` for 1.30) | https://diff.yadz.app/ | `api.json` via Bash/jq, or WebFetch `classes/<Name>/` |
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
| 1.28 / 1.29 / 1.30 compatibility/changes | **READ local compatibility files** |

### Step 2: WebFetch URLs

#### Script API Reference (DIFF, latest PC stable - 1.29)
**Base URL:** `https://diff.yadz.app/` (formerly `dayz-scripts.yadz.app`, which now redirects; the old
Doxygen paths like `/d5/d78/group___enforce` are gone)

The site publishes machine-readable files for agents (see https://diff.yadz.app/agent.md):
| File | Content |
|------|---------|
| https://diff.yadz.app/api.json | Every class, method, field, enum, global, typedef, macro of the latest build (~8.5 MB) |
| https://diff.yadz.app/assets/notes.json | Community notes keyed by `Type` or `Type.Member` (not from BI) |
| https://diff.yadz.app/search.json | Compact name index |
| https://diff.yadz.app/assets/versions.json | Every documented build with its DayZ-Script-Diff commit `sha` |

`api.json` is too large for WebFetch - query it with Bash when available:
```bash
curl -s https://diff.yadz.app/api.json -o /tmp/dayz-api.json   # once per session
jq '.classes[] | select(.name=="CarScript") | {name, base, file}' /tmp/dayz-api.json
jq -c '.classes[] | select(.name=="CarScript").methods[] | select(.name=="UpdateLights")' /tmp/dayz-api.json
curl -s https://diff.yadz.app/assets/notes.json | jq '."ActionBase.ActionCondition"'
```

Without Bash, WebFetch the per-class page:
```
WebFetch(
  url: "https://diff.yadz.app/classes/{CLASS_NAME}/",
  prompt: "Show the inheritance, and the signature of '{METHOD}' (parameters, return type, modifiers)."
)
```

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
