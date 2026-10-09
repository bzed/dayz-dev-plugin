---
name: dayz-dev
description: DayZ development and local DayZ server testing for DayZ 1.29 stable and 1.30 (experimental; stable Oct 15, 2026). Use it for writing, reviewing or porting DayZ mods in Enforce Script (vanilla, Community Framework, Expansion), including class and method lookups, config.cpp, types.xml, RPCs, inventory, vehicles, one build for 1.29 and 1.30 (DAYZ_1_29 / DAYZ_1_30), FindFile and $profile/$mission path breakage, OnCEUpdate/ProcessVariables/vehicle-light changes. Also use it whenever a DayZ dedicated server should be started or tested locally, with or without mods, including finding the Steam DayZServer or experimental server, isolated server trees, free ports, headless boots, stable and experimental side by side, reading script logs and RPTs, even when the user only wants to check that a server or serverDZ.cfg starts. Also for building, signing and publishing mods with armake2 (PBOs, .bikey/.biprivatekey/.bisign, Steam Workshop upload folder; needs bzed's forks of armake2 and steam-workshop-uploader).
allowed-tools: Read, Glob, Grep, WebFetch, WebSearch, Bash(curl:*), Bash(jq:*), Bash(${CLAUDE_SKILL_DIR}/scripts/find-dayzserver.sh:*), Bash(${CLAUDE_SKILL_DIR}/scripts/make-server-tree.sh:*), Bash(${CLAUDE_SKILL_DIR}/scripts/free-ports.sh:*), Bash(${CLAUDE_SKILL_DIR}/scripts/dayz-mod-pack.sh:*), Bash(${CLAUDE_SKILL_DIR}/scripts/dayz-client-headless.sh:*), Bash(${CLAUDE_SKILL_DIR}/scripts/dayz-client-test.sh:*)
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
- **1.30 servers need the profile folder inside the server executable's folder** (symlink ok; `-profiles=profile`, not an
  absolute path elsewhere) and **CF-Test** (+ **COT-Test** if COT is used) until 1.30 stable; Expansion Experimental 1.9.74 targets this.
  CF and our fallback helper both resolve `$profile:` relative to the server folder. See `compatibility/version-130.md` section 2.
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

Where to verify (diff.yadz.app `api.json`, DayZ-Script-Diff, BI wiki, CF, Expansion, dzconfig) and the exact
fetch recipes are in `scripting/api-lookup.md`. Read it before any lookup.

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
| `testing/client-testing.md` | Run the DayZ client headless (sway), join a local server with mods, RPC-driven client+server tests, read client logs | Client-side behavior: UI, replication, RPCs, client script errors |
| `compatibility/version-130.md` | 1.30 changes, dual 1.29/1.30 targeting, FindFile/path rules, review checklist | Any 1.30 question, reviewing/porting a mod, file paths, experimental server |
| `compatibility/YOURMOD_FindFilePath.c` | Fallback FindFile path helper for mods without CF (CF mods use `CF.FindFileEx`) | Any code that calls `FindFile` |
| `compatibility/version-129.md` | 1.29 breaking changes and new features | Version questions, migration (current stable) |
| `compatibility/version-128.md` | 1.28 breaking changes and new features | Migrating from 1.27 or older |
| `scripting/api-lookup.md` | Where to verify classes/tokens, curl/jq/WebFetch recipes for diff.yadz.app, BI wiki, CF, Expansion | Any class/method/token you are not sure about |
| `scripting/best-practices.md` | Enforce Script/memory/null-safety rules, mod folder tree, anti-patterns, modded class/RPC/net-sync snippets | Writing or reviewing code |
| `systems/mod-packaging.md` | armake2 build/sign/binarize, keys, Workshop upload folder, tags, `workshop` uploader (bzed forks required) | Building, signing or publishing a mod |

---

## Request Router

Match the request to a rule, read the file it names, fetch from the web only when the local file does not settle it.

| Request mentions | Action |
|---|---|
| Class or method names (`EntityAI`, `PlayerBase`, `GetInventory()`), "script API" | Look it up (`scripting/api-lookup.md`): `diff.yadz.app/api.json` or DayZ-Script-Diff |
| `CfgVehicles`, `CfgWeapons`, `CfgPatches`, `config.cpp`, `hiddenSelections` | `config/config-cpp.md`, then the BI wiki |
| `types.xml`, `events.xml`, `cfgspawnabletypes.xml`, loot, economy | `config/types-xml.md`, then DayZ-Central-Economy |
| CF, Expansion, `RPCManager`, `ExpansionMarket`, `ModStorage` | `frameworks/framework-detection.md`, then the CF/Expansion docs |
| `ScriptRPC`, `RegisterNetSyncVariable`, `SetSynchDirty`, RPC, sync | `systems/networking.md` |
| `serverDZ.cfg`, `cfgGameplay.json`, BattlEye, admin | `config/server-config.md`, then dzconfig |
| Mod structure, folders, memory, actions, weapons, inventory, vehicles | the matching local file in the map above; `scripting/best-practices.md` for pitfalls |
| Detecting vanilla vs CF vs Expansion (`requiredAddons`, `dependency[]`) | `frameworks/framework-detection.md` |

### Version compatibility (1.30 / 1.29 / 1.28)

**Triggers:** "1.30", "experimental", "DAYZ_1_29", "DAYZ_1_30", "works on both", `FindFile`, `$profile:`, `$mission:`, `$storage:`, backslash paths,
`OnCEUpdate`/`OnCEIterate`, `ProcessVariables`, `VehicleLightsComponent`, `CreateFrontLight`, `Construction`, `CombinationLock`, `GizmoApi`,
`sealed`/`Obsolete`, "breaking change", "migration", "1.29", "1.28".

**Action:** read `compatibility/version-130.md` for anything touching 1.30 and keep the result working on 1.29 (the `DAYZ_1_29`
pattern there). For a mod review walk its checklist (§8) and report findings per item with file:line, then fix with
dual-version code. `version-129.md` covers 1.28 → 1.29, `version-128.md` 1.27 → 1.28. For changes between two builds, diff the
DayZ-Script-Diff commits listed in https://diff.yadz.app/assets/versions.json.

### Testing a mod or a server

**Triggers:** a mod change about to be called done, "test", "verify", "does it load", "start a local server", a `serverDZ.cfg`/mission/
`cfggameplay.json` change, stable vs experimental, `DayZServer`, `-servermod`, `-mod=`, `.RPT`, "mod not loading", "server crashes" - with or without a mod.

**Action:** read `testing/local-server.md`. Locate the server with `${CLAUDE_SKILL_DIR}/scripts/find-dayzserver.sh` (app 223350; `-e` for
Experimental, 1042420). While 1.30 is experimental, boot every change on **both**, one tree each; if one is missing ask the user to
install it through Steam (no steamcmd unless asked). **Never copy, edit or write anything in the Steam directories**: run from a
tree made by `${CLAUDE_SKILL_DIR}/scripts/make-server-tree.sh <tree>` with mods symlinked in and passed as relative `-servermod=`/`-mod=`
paths. **Wipe `mpmissions/*/storage_1` of a tree that already ran before CF or CF-Test is added to it** (CF changes how data is stored; stale storage gives CF/Storage errors; see `testing/local-server.md`). **Never run two servers on one tree** (they lock and corrupt `profiles/`/`mpmissions/`). **Never leave game, Steam query or
RCon ports at the default**: use `${CLAUDE_SKILL_DIR}/scripts/free-ports.sh 3`. A PBO that builds is not a tested mod: boot it and
compare script module counts with vanilla.

**Client side:** when the change is something only a client shows (UI, what replicates to the player, RPCs, client script errors),
read `testing/client-testing.md`. `${CLAUDE_SKILL_DIR}/scripts/dayz-client-test.sh` starts a server and a headless client and returns
the mod's `[AUTOTEST]` results; the example harness is `testing/autotest-mod/`. It needs the user's running Steam, and the one write it
makes outside the tree is a symlink to the test mod in the client's `steamapps/common/DayZ` (clients only load `@mod` folders from
there); remove it afterwards. Never `steam -applaunch` for this: it opens the game on the user's desktop. **One game at a time** (servers:
as many as needed): run `dayz-client-headless.sh status` first, never kill a game you did not start, and stop yours as soon as you
have the logs/screenshots. Experimental has no Workshop: the mods come from stable (`-e` flag, `DayZ Exp` dir; see the Experimental
section of `testing/client-testing.md`).

### Packaging, signing, Workshop upload

**Triggers:** `.pbo`, `.bikey`, `.biprivatekey`, `.bisign`, "sign my mod", "build a PBO", armake2, binarize, the `workshop` uploader, Workshop upload/update, Workshop tags.

**Action:** read `systems/mod-packaging.md`, then drive it with `${CLAUDE_SKILL_DIR}/scripts/dayz-mod-pack.sh` (`init`, `keygen`, `build`, `check`, `publish-hint`).

- **bzed's forks are required, upstream will not do.** armake2 must be https://github.com/bzed/armake2 (upstream leaves `*.c` scripts out of
  the signature hash, so signed script mods fail on servers) and the uploader must be https://github.com/bzed/steam-workshop-uploader
  (it writes/updates `meta.cpp` on DayZ uploads). Look in `$PATH` first and check `armake2 -h 2>&1 | grep -- --proton-binarize`: a hit = the fork (it also binarizes models on Linux). If a tool is missing or is upstream, tell the user and have them install the fork.
- The private key lives in a git-ignored `secrets/`, never in the content folder; never overwrite an existing key.
- Workshop tags: exactly one type tag, `Mod` or `Server` (`Server` = servermods only, never both), plus any number of content tags (Animation, Character, Economy, Environment, Equipment, Mechanics, Sound, Props, Terrain, Vehicle, Weapon). `mod.cpp` is optional; a mod works without it. Plain `build` rapifies configs only; models need `--binarize-models`.
- Uploading to Steam is the user's call: print the `workshop` command with `publish-hint`, never run it unprompted.

### Local knowledge

Mod structure, PBO packaging, best practices, anti-patterns, memory management, actions, weapons, inventory: read the matching local file.

---

## Related Skills

| Need | Skill |
|------|-------|
| UI/HUD design | Read `scripting/` files for Widget system |
| Server administration | Read `config/server-config.md` |
| Expansion modding | Read `frameworks/expansion.md` |
| Version migration | Read `compatibility/version-130.md` (1.30 + dual targeting), `version-129.md`, `version-128.md` |
