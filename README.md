# DayZ Development Plugin

A comprehensive plugin for DayZ mod development with Enforce Script and for testing local DayZ dedicated servers. Provides dynamic documentation fetching, framework support for vanilla, Community Framework, and DayZ Expansion, and a tested workflow for starting stable and experimental servers headless, with or without mods.

**Supports:** Claude Code, Gemini Code Assist, Cursor, Windsurf, and other AI coding assistants.
**Target Versions:** DayZ 1.29 (v1.29.163709, stable) and 1.30 (v1.30.164014, experimental; stable Oct 15, 2026), with 1.28 migration notes

## Features

- **Dynamic Documentation Fetching** - Fetches up-to-date script API, config references, and mod docs via WebFetch
- **Multi-Framework Support** - Vanilla, Community Framework (CF), DayZ Expansion with auto-detection
- **Enforce Script Correctness** - Never outputs C#/C++ syntax, always uses proper Enforce Script
- **No-Hallucination Policy** - Verifies all classes, methods, and config tokens against documentation
- **1.30 / 1.29 / 1.28 Compatibility** - Breaking changes, migration guides, and new features; 1.30 verified on stable and experimental dedicated servers, including how to keep one mod working on both
- **Local Server Testing** - Find the Steam-installed DayZ Server (stable or experimental), build an isolated server tree, pick free ports, boot it headless and read the logs. Works for a vanilla server, a mission or `serverDZ.cfg` change, or a mod
- **Best Practices** - Null safety, server/client context, memory management, performance patterns

## Installation

### Claude Code (Git)

```bash
git clone https://github.com/DayZGhost/dayz-dev-plugin.git ~/.claude/skills/dayz-dev
```

### Gemini Code Assist

1. Copy the `.gemini/` directory to your DayZ mod project root
2. Copy the knowledge files (`scripting/`, `systems/`, `frameworks/`, `config/`, `testing/`, `compatibility/`) alongside it
3. Gemini Code Assist automatically loads `.gemini/GEMINI.md` as project context

```bash
git clone https://github.com/DayZGhost/dayz-dev-plugin.git /tmp/dayz-dev
cp -r /tmp/dayz-dev/.gemini /tmp/dayz-dev/scripting /tmp/dayz-dev/systems /tmp/dayz-dev/frameworks /tmp/dayz-dev/config /tmp/dayz-dev/testing /tmp/dayz-dev/compatibility your-project/
```

### Cursor / Windsurf

1. Download `DAYZ_CURSOR_RULES.md` from this repo
2. Copy to your DayZ mod project root as `.cursorrules`

```bash
curl -o .cursorrules https://raw.githubusercontent.com/DayZGhost/dayz-dev-plugin/main/DAYZ_CURSOR_RULES.md
```

### Manual

1. Download/clone this repository
2. Copy to `~/.claude/skills/dayz-dev/`
3. Restart your AI assistant

## Usage

### Automatic (Skill)

The skill activates automatically when you ask DayZ-related questions:

- "How do I create a custom item in DayZ?"
- "What's the config.cpp format for a new weapon?"
- "How does the CF RPCManager work?"
- "Show me the Expansion market trader config"
- "What broke in 1.29?"
- "Review my mod for 1.30 without breaking 1.29"
- "Why does FindFile not find my JSON files on experimental?"
- "Start a local 1.30 experimental server and check that it boots"
- "Does our serverDZ.cfg / cfggameplay.json change still start on stable?"

### Command

Use the `/dayz-dev` command for direct queries:

```
/dayz-dev How to create a modded class for PlayerBase?
/dayz-dev What are the NetSync variable types?
/dayz-dev Expansion quest system setup
/dayz-dev 1.29 vehicle headlight changes
/dayz-dev review @MyMod for 1.30
```

## Documentation Sources

| Source | URL | Coverage |
|--------|-----|----------|
| DIFF (DayZ Scripts API) | https://diff.yadz.app/ | Script API of the latest build (1.29), `api.json`, per-build changelog |
| DayZ Script Diff | https://github.com/BohemiaInteractive/DayZ-Script-Diff | Official source code changes |
| BI Community Wiki | https://community.bistudio.com/wiki/DayZ:Enforce_Script_Syntax | Language reference |
| DayZ Explorer | https://dayzexplorer.zeroy.com/ | Enforce essentials, Math, FileIO |
| Community Framework | https://github.com/Arkensor/DayZ-CommunityFramework | CF source + docs |
| Expansion Wiki | https://github.com/salutesh/DayZ-Expansion-Scripts/wiki | 119+ wiki pages |
| DZconfig Wiki | https://dzconfig.com/wiki/ | Server configuration |
| Central Economy | https://github.com/BohemiaInteractive/DayZ-Central-Economy | types.xml, events.xml |

## Skill Files

| Directory | Contents |
|-----------|----------|
| `SKILL.md` | Main orchestrator with decision tree and verification rules |
| `.gemini/` | Gemini Code Assist context files (GEMINI.md, styleguide.md) |
| `scripting/` | Enforce Script language, class hierarchy, client-server, memory management |
| `systems/` | Mod structure, PBO packaging/signing/Workshop upload (armake2), networking, inventory, actions, weapons, vehicles |
| `frameworks/` | Framework detection, Community Framework, Expansion |
| `config/` | config.cpp, types.xml, server configuration |
| `compatibility/` | Version 1.30, 1.29 and 1.28 breaking changes and migration guides; `CF.FindFileEx` guidance and fallback `FindFile` path helper |
| `testing/` | Testing a mod headless on the Steam-installed local DayZ Server (stable and experimental) |
| `scripts/` | `find-dayzserver.sh` (locate Steam app 223350, or 1042420 experimental with `-e`, and workshop mods), `make-server-tree.sh` (private server tree symlinked into Steam), `free-ports.sh` (random non-default ports), `dayz-mod-pack.sh` (armake2 from PATH, which must be the https://github.com/bzed/armake2 fork (upstream signs wrongly), with the upstream https://github.com/nozwock/steam-workshop-uploader uploader: keygen, build and sign PBOs, optional model binarization, assemble the Workshop upload folder), installer |
| `commands/` | `/dayz-dev` slash command template |

## What's Covered

### Enforce Script
- Complete language reference (types, operators, control flow, classes)
- Modded class injection patterns
- Memory management (ref, autoptr, Managed)
- Templates, enums, casting, preprocessor

### DayZ Systems
- Mod folder structure and PBO packaging; armake2 keygen/build/sign and Workshop upload folder
- RPC systems (vanilla ScriptRPC + CF RPCManager)
- Net sync variables and CF NetworkedVariables
- Inventory system (locations, creation, movement)
- Action system (interact, continuous, single-use, firearm)
- Weapon system (FSM, configs, scripting)
- Vehicle system (configs, physics, 1.28/1.29 changes)

### Frameworks
- Vanilla, CF, and Expansion auto-detection
- CF Modules, RPCManager, ModStorage
- Expansion Market, Quests, AI, Basebuilding, Vehicles

### Configuration
- config.cpp (CfgPatches, CfgMods, CfgVehicles, CfgWeapons)
- types.xml and Central Economy
- Server configuration (serverDZ.cfg, cfgGameplay.json)
- 1.28 enhanced spawnabletypes.xml

### 1.30 Compatibility (experimental, stable Oct 15, 2026)
- Dual targeting with the engine's `DAYZ_1_29` / `DAYZ_1_30` defines (one PBO for both)
- `FindFile` ignores `$profile:`/`$mission:` placeholders and backslashes on 1.30: use `CF.FindFileEx` (fallback helper without CF: `compatibility/YOURMOD_FindFilePath.c`)
- Compile breakers (`ProcessVariables(float)`, `Construction.SetParent`, `ToggleHeadlights`), silent breakers (`OnCEUpdate` never called, car light profiles), obsolete inventory API, ERPCs shift
- Review checklist; every key claim tested on 1.29.163709 and 1.30.164014 dedicated servers

### 1.29 Compatibility
- `GetGame()` now a script wrapper around `g_Game`, `ActiveState` enum reorder, native vehicle headlights
- Juncture `userData`, `InventoryLocationType.TEMP`, stamina rework, `EntityType` classes, `GizmoApi`
- New scripted physics API, Transport forces, cached equipment, newly obsolete APIs
- Migration checklist, verified against the DayZ-Script-Diff 1.28.161464 → 1.29.163709 diff

### 1.28 Compatibility
- 12 breaking changes documented with before/after code
- Migration checklist
- New features (sealed, Obsolete, new Entity methods)
- Framework version requirements

## Contributing

1. Fork the repository
2. Create your feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

## License

GNU General Public License v3.0 - see [LICENSE](LICENSE).

## Credits

- Bohemia Interactive - DayZ, Enforce Script, official documentation
- TrueDolphin - [EnScript Style Guide](https://github.com/TrueDolphin/references/wiki/EnScript-(Enforce-Script)-Style-Guide) - Naming conventions, memory management patterns, common pitfalls
- Arkensor - Community Framework
- salutesh - DayZ Expansion Scripts
- DayZ modding community - DayZ Explorer, DIFF (diff.yadz.app), community wikis
- DZconfig.com - Server configuration wiki
- FiveM Dev Plugin (melihbozkurt10) - Architectural inspiration
