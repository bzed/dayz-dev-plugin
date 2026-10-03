---
name: dayz-dev
description: DayZ development and local DayZ server testing for DayZ 1.29 stable and 1.30 (experimental; stable Oct 15, 2026). Use it for writing, reviewing or porting DayZ mods in Enforce Script (vanilla, Community Framework, Expansion), including class and method lookups, config.cpp, types.xml, RPCs, inventory, vehicles, keeping one build working on 1.29 and 1.30 (DAYZ_1_29 / DAYZ_1_30), FindFile and $profile/$mission path breakage, OnCEUpdate/ProcessVariables/vehicle-light changes. Also use it whenever a DayZ dedicated server should be started or tested locally, with or without mods, including finding the Steam DayZServer or experimental server, building an isolated server tree, free ports, headless boots, stable and experimental side by side, and reading script logs and RPTs for compile errors or crashes, even when the user only wants to check that a server, mission or serverDZ.cfg starts. Also use it for building, signing and publishing mods with armake2 (PBOs, .bikey/.biprivatekey/.bisign keys, binarizing configs, preparing a Steam Workshop upload folder for the workshop uploader).
allowed-tools: Read, Glob, Grep, WebFetch, WebSearch, Bash(curl:*), Bash(jq:*), Bash(${CLAUDE_SKILL_DIR}/scripts/find-dayzserver.sh:*), Bash(${CLAUDE_SKILL_DIR}/scripts/make-server-tree.sh:*), Bash(${CLAUDE_SKILL_DIR}/scripts/free-ports.sh:*), Bash(${CLAUDE_SKILL_DIR}/scripts/dayz-mod-pack.sh:*)
---

# DayZ Development

> **Dynamic documentation orchestrator** for DayZ mod development.
> Supports vanilla Enforce Script, Community Framework (CF), and DayZ Expansion.
> Target versions: **DayZ 1.29 (v1.29.163709, stable)** and **1.30 (v1.30.164014, experimental; stable release Oct 15, 2026)**.
> Until 1.30 is stable, code must run on **both**. 1.28 notes kept for migration.

## Philosophy

1. **Fetch, don't memorize** - Always get latest from authoritative sources
2. **Framework-aware thinking** - Detect vanilla vs CF vs Expansion, adapt patterns
3. **Enforce Script correctness** - DayZ uses Enforce Script (C-like), NOT C#/C++/Lua
4. **Server-side validation** - Never trust client-side data
5. **Null-safe always** - Every Cast<>, GetInventory(), GetIdentity() must be null-checked

---

## Two Releases at Once (1.29 stable + 1.30 experimental)

Every mod change has to keep working on 1.29 and be correct on 1.30. Read `compatibility/version-130.md`
for any review, port or "does this still work" question. The essentials, all verified on real servers:

- **The engine defines the version**: `DAYZ_1_29` on 1.29, `DAYZ_1_30` on 1.30 (only the current one).
  Put the *old* code under `#ifdef DAYZ_1_29` and the new code in `#else`, so the new path stays the default
  on 1.31+. The same PBO then loads on both. Prefer APIs that exist in both versions over `#ifdef`.
- **`FindFile` ignores `$profile:`/`$mission:`/`$storage:`/`$saves:` on 1.30** and silently searches the
  server root instead. Replace every `FindFile` with `CF.FindFileEx` (CF-Test now, in CF from the 1.30 release; it detects the bug and
  calls `CF.ResolvePath`); without a CF dependency use the fallback `compatibility/YOURMOD_FindFilePath.c`. All other file
  functions still accept the placeholders.
- **Paths use forward slashes.** Backslashes break `FindFile` on 1.30; forward slashes work everywhere on both.
- **Compile breakers**: `ProcessVariables()` → `ProcessVariables(float elapsedTime)`,
  `Construction.SetParent(EntityAI)`, `CarScript.ToggleHeadlights()` removed (use `LightToggle()`).
- **Silent breakers**: `OnCEUpdate()` overrides compile but are never called (use `OnCEIterate`);
  custom car `CreateFrontLight()` is never called (use `VehicleLightsComponent` profiles).
- **Experimental is a diag build** (`DIAG_DEVELOPER`, `BUILD_EXPERIMENTAL`): never use those defines as
  "is 1.30", and expect `Error()`/`ErrorEx()` to show up as VM exceptions there.
- Remote API references (diff.yadz.app, DayZ-Script-Diff) may still show 1.29. When a local copy of the
  1.30 scripts exists (ask the user; e.g. a git with `1.29`/`1.30` tags), check signatures there, or use
  `https://diff.yadz.app/v/experimental/`.

---

## CRITICAL: No Hallucination Policy

**NEVER invent or guess Enforce Script classes, methods, config tokens, or parameters.**

### Rules:
1. **If unsure about a class/method** -> MUST fetch from DayZ Scripts API or Script Diff repo
2. **If unsure about config.cpp tokens** -> MUST fetch from BI wiki or DayZ Central Economy repo
3. **If a class doesn't exist** -> Tell user honestly, suggest alternatives
4. **If parameters unknown** -> Fetch documentation, don't guess
5. **NEVER use C#/C++ syntax** -> Enforce Script looks like C but has key differences

### Before writing any class or method call:
- [ ] Is this a real DayZ class? -> Verify at diff.yadz.app (api.json) or DayZ-Script-Diff
- [ ] Is this the correct method signature? -> Check parameter types and order
- [ ] Does this work on server/client/both? -> Check script module (3_Game/4_World/5_Mission)
- [ ] Am I null-checking accessors? -> Cast<>, GetInventory(), GetIdentity(), GetPlayer()

### When you don't know:
```
"I'm not 100% certain about this class/method. Let me fetch the documentation..."
[Use WebFetch to get accurate info]
```

### Verification Sources:
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

### Example - WRONG:
```csharp
// DON'T: Using C# syntax or inventing methods
player.GetComponent<Inventory>().AddItem("AK74");  // NOT Enforce Script!
```

### Example - RIGHT:
```c
// DO: Use verified Enforce Script with null checks
PlayerBase player = PlayerBase.Cast(GetGame().GetPlayer());
if (player)
{
    EntityAI item = player.GetInventory().CreateInInventory("AKM");
    if (item)
    {
        // item created successfully
    }
}
```

---

## Content Map

**Read ONLY relevant files based on the request:**

| File | Description | When to Read |
|------|-------------|--------------|
| `scripting/enforce-script.md` | Enforce Script language quick reference | Writing any code |
| `scripting/class-hierarchy.md` | Class tree and key singletons | Looking up classes |
| `scripting/client-server.md` | Script module architecture | New mod, client/server questions |
| `scripting/memory-management.md` | ref, autoptr, Managed patterns | Memory/lifecycle issues |
| `systems/mod-structure.md` | Mod folders, config.cpp, meta.cpp | Creating new mods |
| `systems/networking.md` | RPC, NetSync, CF NetworkedVariables | Multiplayer sync |
| `systems/inventory.md` | Inventory system, InventoryLocation | Item manipulation |
| `systems/actions.md` | Action system hierarchy | Custom actions |
| `systems/weapons.md` | Weapon FSM, configs | Weapon mods |
| `systems/vehicles.md` | Vehicle config, SimulationModule | Vehicle mods |
| `frameworks/framework-detection.md` | Detect vanilla vs CF vs Expansion | Starting new task |
| `frameworks/community-framework.md` | CF modules, RPC, NetworkedVariables | Using CF |
| `frameworks/expansion.md` | Expansion systems overview | Using Expansion |
| `config/config-cpp.md` | config.cpp reference and patterns | Item/vehicle config |
| `config/types-xml.md` | types.xml, economy system | Loot spawning |
| `config/server-config.md` | Server configuration files | Server setup |
| `testing/local-server.md` | Find the Steam-installed DayZ Server, build a symlinked server tree, run a mod headless, read the logs | Testing/verifying any mod change |
| `compatibility/version-130.md` | 1.30 changes, dual 1.29/1.30 targeting, FindFile/path rules, review checklist | Any 1.30 question, reviewing/porting a mod, file paths, experimental server |
| `compatibility/YOURMOD_FindFilePath.c` | Fallback FindFile path helper for mods without CF (CF mods use `CF.FindFileEx`) | Any code that calls `FindFile` |
| `compatibility/version-129.md` | 1.29 breaking changes and new features | Version questions, migration (current stable) |
| `compatibility/version-128.md` | 1.28 breaking changes and new features | Migrating from 1.27 or older |

---

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

---

## Request Router - Pattern Matching

### RULE 1: Enforce Script Class/Method Detection
**Triggers when:**
- Class names (PascalCase like `EntityAI`, `PlayerBase`, `ItemBase`, `CarScript`)
- Method calls (`GetInventory()`, `CreateInInventory()`, `SetHealth()`)
- "enforce script", "dayz class", "dayz method", "script API"

**Action:** Look up in `https://diff.yadz.app/api.json` (or `classes/<Name>/`) or `DayZ-Script-Diff`

### RULE 2: Config.cpp / CfgVehicles Detection
**Triggers when:**
- `CfgVehicles`, `CfgWeapons`, `CfgMagazines`, `CfgAmmo`
- `CfgPatches`, `CfgMods`, `DamageSystem`
- "config.cpp", "model config", "item config", "vehicle config"
- `scope`, `displayName`, `model`, `hiddenSelections`

**Action:** Read local `config/config-cpp.md` + Fetch from BI wiki if needed

### RULE 3: Central Economy Detection
**Triggers when:**
- `types.xml`, `events.xml`, `cfgspawnabletypes.xml`, `cfgeconomycore.xml`
- "loot spawn", "item spawn", "economy", "nominal", "min", "restock"
- `randompresets.xml`, `cfgenvironment.xml`

**Action:** Read local `config/types-xml.md` + Fetch from DayZ-Central-Economy repo

### RULE 4: CF / Expansion Framework Detection
**Triggers when:**
- `RPCManager`, `CF_ModuleWorld`, `NetworkedVariables`, `ModStorage`
- `ExpansionMarket`, `ExpansionQuest`, `ExpansionAI`, `ExpansionTerritory`
- "community framework", "CF module", "expansion", "market system"

**Action:** Detect framework -> Fetch from appropriate docs

### RULE 5: Networking / RPC Detection
**Triggers when:**
- `ScriptRPC`, `GetRPCManager()`, `SendRPC`, `AddRPC`
- `RegisterNetSyncVariable`, `SetSynchDirty`, `OnVariablesSynchronized`
- "sync variable", "RPC", "network", "client-server communication"

**Action:** Read local `systems/networking.md` + Fetch if needed

### RULE 6: Server Configuration Detection
**Triggers when:**
- `serverDZ.cfg`, `cfgGameplay.json`, `storage_1`
- "server config", "gameplay settings", "admin", "BattlEye"

**Action:** Read local `config/server-config.md` + Fetch from DZconfig wiki

### RULE 7: Version Compatibility (1.30 / 1.29 / 1.28)
**Triggers when:**
- "1.30", "experimental", "Oct 15", "DAYZ_1_29", "DAYZ_1_30", "review for 1.30", "works on both"
- `FindFile`, `$profile:`, `$mission:`, `$storage:`, backslash paths, `OnCEUpdate`, `OnCEIterate`, `ProcessVariables`,
  `VehicleLightsComponent`, `CreateFrontLight`, `TakeEntityToCargo`, `CombinationLock`, `Construction`
- "1.29", "1.28", "update", "breaking change", "migration", "compatibility"
- `ActiveState`, `LightIsOn`, `m_HeadlightsOn`, `EntityType`, `GizmoApi`, `GetCachedEquipment`, juncture `userData`
- `sealed`, `Obsolete`, `Contact`, `SurfaceProperties`
- "vehicle brake", "useNewNetworking", "parameter limit", "headlights"

**Action:** Read local `compatibility/version-130.md` for anything touching 1.30, and keep the result working on 1.29
(the `DAYZ_1_29` pattern there). For a mod review, walk its checklist (§8) and report findings per item with
file:line, then fix with dual-version code. `compatibility/version-129.md` covers 1.28 → 1.29,
`compatibility/version-128.md` 1.27 → 1.28.
For changes between two specific builds, diff the DayZ-Script-Diff commits listed in
https://diff.yadz.app/assets/versions.json.

### RULE 8: Testing a Mod or a Server
**Triggers when:**
- A mod change is about to be called done, or "test", "verify", "does it load", "run the server"
- "start a local server", "test server", "does the server start", trying a mission, `serverDZ.cfg` or
  `cfggameplay.json` change, comparing stable vs experimental - **with or without any mod**
- `DayZServer`, `-servermod`, `-mod=`, `script_*.log`, `.RPT`, "compile error", "mod not loading", "server crashes"

**Action:** Read local `testing/local-server.md` - it applies to a plain vanilla server just as well
(skip the mod steps). Locate the server with
`${CLAUDE_SKILL_DIR}/scripts/find-dayzserver.sh` (Steam app 223350; `-e` finds the Experimental
Server, app 1042420). While 1.30 is on experimental, boot every change on **both**, one tree each. If one is missing, ask the
user to install it through Steam - do not set up steamcmd unless they ask. **Never copy, edit or
write anything in the Steam directories**: run the server from a tree of your own made by
`${CLAUDE_SKILL_DIR}/scripts/make-server-tree.sh <tree>`, with mods symlinked into it
(workshop mods from `find-dayzserver.sh -w`) and passed as relative `-servermod=`/`-mod=` paths.
**Never run two servers on the same tree** (same `profiles/` or `mpmissions/`): they lock those
folders and corrupt each other. For parallel debugging build one tree per server. **Never leave
the game, Steam query or RCon port at its default**: take random free ones from
`${CLAUDE_SKILL_DIR}/scripts/free-ports.sh 3` for every server.
A PBO that builds is not a tested mod: boot it and compare the script module counts with vanilla.

### RULE 8b: Packaging, Signing, Workshop Upload
**Triggers when:**
- `.pbo`, `.bikey`, `.biprivatekey`, `.bisign`, "sign my mod", "build a PBO", armake2, binarize, `workshop` uploader, Workshop upload/update

**Action:** Read local `systems/mod-packaging.md`. Find `armake2` in PATH first and check `armake2 --help` (needs the bzed fork https://github.com/bzed/armake2:
`paa2img` present; `proton-binarize` present = can binarize models on Linux; upstream fails on DayZ configs); build the fork only if missing or too old. Use it via `${CLAUDE_SKILL_DIR}/scripts/dayz-mod-pack.sh` (`init`, `keygen`, `build`, `check`,
`publish-hint`; `build --binarize-models` also converts models via Proton on Linux). The private key stays in a git-ignored `secrets/`, never in the content folder; never overwrite an
existing key. Workshop tags: `Mod` is required, `Server` marks server-side content (there is no `servermod` tag); `build` writes meta.cpp (publishedid 0 until the item exists; client mods need the real id). Plain `build` rapifies configs only (p3d/rtm stay MLOD unless `--binarize-models`). Uploading to Steam is the user's
call: print the `workshop` command, do not run it unprompted.

### RULE 9: Local Knowledge
**Triggers when:**
- Mod structure, folder layout, PBO packaging
- Best practices, anti-patterns, common pitfalls
- Memory management, lifecycle patterns
- Action system, weapon system, inventory system

**Action:** Read relevant local markdown file

---

## Mod Framework Auto-Detection

When starting a task, detect what frameworks the mod uses:

### Check config.cpp dependencies
```cpp
// Vanilla only
requiredAddons[] = {"DZ_Data"};

// Community Framework
requiredAddons[] = {"DZ_Data", "JM_CF_Scripts"};

// Expansion
requiredAddons[] = {"DZ_Data", "JM_CF_Scripts", "DayZExpansion_Core"};
```

### Check script imports
```c
// CF detection
GetRPCManager()     // Uses CF RPC system
CF_ModuleWorld      // Uses CF Module system

// Expansion detection
ExpansionMarketModule       // Uses Expansion Market
ExpansionQuestModule        // Uses Expansion Quests
eAIBase                     // Uses Expansion AI
```

### Check mod.cpp / meta.cpp
```
// CF dependency
dependency[] = {"Community Framework"};

// Expansion dependency
dependency[] = {"DayZ Expansion Core", "DayZ Expansion Scripts"};
```

---

## Best Practices (Quick Reference)

### Enforce Script Rules
| Rule | Why |
|------|-----|
| Use `!GetGame().IsDedicatedServer()` for client check | `IsClient()` returns FALSE during init |
| Assign getter results to local var before foreach | `foreach` on inline getter returns fails |
| Always parenthesize bitwise ops: `(a & b) == b` | Bitwise ops have lower precedence than comparisons |
| Use `ref` ONLY for member variables | `ref` in function params is WRONG |
| Check last file before reported error location | Compiler errors often point to wrong file |
| Never leave empty preprocessor blocks | Can cause segfaults |

### Memory Management Rules
| Rule | Why |
|------|-----|
| `ref` for member variables only | Controls reference lifetime |
| Never `delete` manually | Enforce Script uses GC |
| Inherit from `Managed` for ref counting | Enables `ref`/`autoptr` usage |
| `autoptr` auto-deletes when scope exits | Use for temporary owned references |

### Null Safety Rules
| Rule | Example |
|------|---------|
| Always check `Cast<>` results | `PlayerBase p = PlayerBase.Cast(entity); if (p) {...}` |
| Always check `GetInventory()` | `if (player.GetInventory()) {...}` |
| Always check `GetIdentity()` | `if (player.GetIdentity()) {...}` |
| Always check `GetGame().GetPlayer()` | Can be null during init/cleanup |

### Security Rules
| Rule | Reason |
|------|--------|
| Validate on server side | Client can be tampered |
| Check `GetGame().IsServer()` before gameplay logic | Prevent client-side exploitation |
| Use RPC callbacks, not direct events | Prevent event spoofing |
| Validate player identity on server RPCs | Prevent impersonation |

### Mod Structure
```
MyMod/
├── mod.cpp                    # Mod metadata
├── meta.cpp                   # Workshop metadata (auto-generated)
├── Keys/                      # BIS key for server signing
├── Addons/
│   └── MyMod/
│       ├── config.cpp         # CfgPatches, CfgMods, CfgVehicles
│       ├── $PREFIX$            # Mod prefix file
│       └── scripts/
│           ├── config.cpp     # Script module registration
│           ├── 3_Game/        # Game-level scripts (available everywhere)
│           ├── 4_World/       # World-level scripts (entities, items, players)
│           └── 5_Mission/     # Mission-level scripts (HUD, menus, mission logic)
```

---

## Anti-Patterns

| Don't | Do |
|-------|-----|
| `GetGame().IsClient()` during init | `!GetGame().IsDedicatedServer()` |
| `foreach (auto x : GetSomething())` | `auto list = GetSomething(); foreach (auto x : list)` |
| `if (flags & FLAG == FLAG)` | `if ((flags & FLAG) == FLAG)` |
| `ref` in function parameters/returns/locals | `ref`/`autoptr` only for class member variables |
| Add `: ParentClass` to `modded class` | `modded class` already inherits - never add inheritance |
| `delete obj;` | `obj = null;` (let GC handle cleanup) |
| Trust client data in RPCs | Always validate server-side |
| `GetGame()` | Use `g_Game` global (1.29: `GetGame()` is just a script wrapper around `g_Game`) |
| `SurfaceIsPond()` / `SurfaceIsSea()` | `g_Game.GetWaterDepth(pos) <= 0` (much faster) |
| `GetObjectsAtPosition()` frequently | Cache results, use triggers, or keep your own registry of relevant objects |
| Empty `#ifdef` / `#endif` blocks | Always have content or remove entirely |
| Hardcode framework dependencies | Detect at runtime via config.cpp |
| Skip null checks on Cast<> | Always check before using result |
| Write files outside `$profile:`/`$saves:`/`$mission:` | Server FileIO is sandboxed to those; `$storage:` works only after the first tick following `OnMissionStart` and not on a first boot (no `storage_1`) |
| `FindFile("$profile:...")` | `CF.FindFileEx("$profile:...", ...)` (or `FindFile(YOURMOD_FindFilePath(...))` without CF) - 1.30 ignores placeholders in `FindFile` |
| Backslashes in paths (`"$profile:MyMod\\cfg.json"`) | Forward slashes (`"$profile:MyMod/cfg.json"`) - required for `FindFile` on 1.30 |
| `g_Game.GetMissionFolderPath()` | Folder of `g_Game.GetMissionPath()` - the former is `""` on servers |
| `override void OnCEUpdate()` | `OnCEIterate(float currentTime, float elapsedTime)` on 1.30 (`#ifdef DAYZ_1_29` for the old one) |
| New-version code under `#ifdef DAYZ_1_30` | Old code under `#ifdef DAYZ_1_29`, new code in `#else` (stays on for 1.31+) |
| `#ifdef BUILD_EXPERIMENTAL`/`DIAG_DEVELOPER` as "is 1.30" | `DAYZ_1_29`/`DAYZ_1_30` - the diag defines vanish on stable |
| Unqualified member names in modded classes | Prefix with mod name: `m_MyMod_VarName` |

---

## DayZ-Specific Patterns

### Modded Class Injection (The DayZ Way)
```c
modded class PlayerBase
{
    override void SetActions(out TInputActionMap InputActionMap)
    {
        super.SetActions(InputActionMap);
        AddAction(MyCustomAction, InputActionMap);
    }
}
```

### RPC Communication (Vanilla)
```c
// Server -> Client
ScriptRPC rpc = new ScriptRPC();
rpc.Write(someData);
rpc.Send(player, ERPCs.RPC_USER_ACTION_MESSAGE, true, player.GetIdentity());

// Client handler
void OnRPC(PlayerIdentity sender, Object target, int rpc_type, ParamsReadContext ctx)
{
    if (rpc_type == ERPCs.RPC_USER_ACTION_MESSAGE)
    {
        ctx.Read(someData);
    }
}
```

### RPC Communication (CF)
```c
// Register
GetRPCManager().AddRPC("MyMod", "MyRPCHandler", this, SingeplayerExecutionType.Both);

// Send
GetRPCManager().SendRPC("MyMod", "MyRPCHandler", new Param1<string>("data"), true, null);

// Handler
void MyRPCHandler(CallType type, ParamsReadContext ctx, PlayerIdentity sender, Object target)
{
    Param1<string> data;
    if (!ctx.Read(data)) return;
    // process data.param1
}
```

### Player Lifecycle Events
```
OnInit -> InvokeOnConnect -> OnClientReadyEvent -> OnClientDisconnectedEvent -> MissionFinish
```

### Net Sync Variables
```c
class MyEntity extends ItemBase
{
    int m_MyValue;

    void MyEntity()
    {
        RegisterNetSyncVariableInt("m_MyValue", 0, 100);
    }

    void SetMyValue(int val)
    {
        m_MyValue = val;
        SetSynchDirty();
    }

    override void OnVariablesSynchronized()
    {
        super.OnVariablesSynchronized();
        // m_MyValue is now updated on client
    }
}
```

---

## Related Skills

| Need | Skill |
|------|-------|
| UI/HUD design | Read `scripting/` files for Widget system |
| Server administration | Read `config/server-config.md` |
| Expansion modding | Read `frameworks/expansion.md` |
| Version migration | Read `compatibility/version-130.md` (1.30 + dual targeting), `version-129.md`, `version-128.md` |
