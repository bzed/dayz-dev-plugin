# DayZ Expansion Framework

> **Steam Workshop:** Multiple modules (Core, Scripts, Market, Quests, AI, etc.)
> **GitHub:** https://github.com/salutesh/DayZ-Expansion-Scripts
> **Wiki:** https://github.com/salutesh/DayZ-Expansion-Scripts/wiki
> **Minimum for 1.28:** Expansion 1.9.28

## Requirements (read this first)

**DayZ-Expansion-Bundle does not run on its own.** It needs three other mods, loaded before it:

1. **Community Framework** (CF): `JM_CF_Scripts`. Use the current Workshop CF (1.5.9+); CF-Test is not needed.
2. **Dabs Framework**: not pulled in by the Bundle or by CF, and not mentioned in Expansion's own mod list. Without it the Game module fails to compile (see below).
3. **DayZ-Expansion-Licensed**: the licensed assets and scripts the Bundle's modules depend on (a separate Workshop item).

Then the Bundle, then your mod. A server that misses any of the three fails in script compile, usually with a
first error followed by hundreds of cascade errors. Fix the first one.

### On DayZ 1.30 (stable)

A 1.30 server needs:

- The regular **Licensed** and **Bundle** items (the `-experimental` variants were only for the 1.30 pre-release).
- The regular **Dabs Framework** Workshop build, unpatched (Expansion and Dabs run as published on 1.30 stable on the
  user's servers) (tested). The Workshop Dabs build did not compile on the 1.30 pre-release, which is why older notes mention a patched fork.
- On 1.30 builds before 1.30.164200 only: the profile folder inside the server executable's folder (a symlink works), because vanilla
  `FindFile` was broken there (DZEXP-134). Since 1.30.164200 (build 25963285) `FindFile` is fixed and any `-profiles=` works (tested with vanilla and CF).
- No `-newErrorsAreWarnings=1` and no script patches for Expansion or Dabs: both were pre-release workarounds only.

Not re-checked here against the 1.30 release build: the Workshop Licensed/Bundle ids. Boot it and read `script_*.log` before
relying on the table. Details:
`frameworks/community-framework.md`, `compatibility/version-130.md` section 2.

Example start (mods in load order):

```
"-mod=@CF;@DabsFramework;@DayZ-Expansion-Licensed;@DayZ-Expansion-Bundle;@YourMod" \
  -profiles=profile
```

## Local test server with Expansion: the full mod set

Load these, **in this order** (Workshop ids; `-mod=` / symlinked `@` folders):

| # | Mod | Workshop id |
|---|-----|-------------|
| 1 | Community Framework (1.5.9+) | 1559212036 |
| 2 | **Dabs Framework** (required) | 2545327648 (Workshop build, unpatched on 1.30) |
| 3 | DayZ-Expansion-Licensed (required) | 2116157322 (the pre-release used 2178159769, Licensed-Experimental) |
| 4 | DayZ-Expansion-Bundle (all modules, incl. Navigation, Vehicles, Garage) | 2572331007 (the pre-release used 2540096189, Bundle-Experimental) |
| 5 | optional: DayZ-Expansion-Animations (needed to drive Expansion cars and helicopters) | 2918418331 |
| 6 | your mod (last) | |

All keys come with the mods (`keys/*.bikey`).

- **With the Bundle, Licensed is the only other Expansion item you need.** The Bundle contains every module
  (Spawn-Selection, Market, Quests, AI, ...), so do not add the single-module items (e.g. DayZ-Expansion-Spawn-Selection, 2804241648). (tested)
- Booted with CF, Dabs, Licensed, Bundle (ids above): 1081 Game-module files, no `SCRIPT (E)`, a headless client joined and
  was in the world. (tested, server and client 1.30.164078.38)

- **Without Dabs** the Game module fails with `Undefined function 'Math.Exp'` (Dabs defines `Math.Exp`),
  followed by hundreds of `Bad type 'JsonFileLoader'` / `'array'` cascade errors. Fix the first error, not the cascade. (tested)
- **Pre-release only (1.30.164014):** the Workshop Dabs build (2545327648) failed with
  `DabsFramework/.../MVC/Types/Types.c(52): Syntax error` and needed a patched fork (`fix/1.30-compat-staging`); Expansion 1.9.76
  (Experimental items) booted with that fix. On the stable 1.30 release neither patch is needed.
  On that diag build the Expansion AI NPC classes (`ExpansionQuestNPCAI*`, `ExpansionP2PTraderAI*`) threw
  `Index out of bounds` VM exceptions in the hundreds: Expansion's own, unrelated to your mod. (tested on the pre-release)
- **Screenshots / item handling on a client:** the Expansion spawn selector blocks them; disable it first, see the recipe in
  `testing/client-testing.md` ("Expansion bundle: skip the spawn selector"). The ready-made headless run for this set is in the
  same file, "Example: Expansion bundle screenshot".
- Navigation/Vehicles are detected with `#ifdef EXPANSIONMODNAVIGATION` / `EXPANSIONMODVEHICLE` (defined by the Expansion preload
  scripts, so they work whatever the mod order).
- `modded class` must live in the **same script module as the class it modifies**: `Transport` is a `3_Game` class, so
  `modded class Transport` in `4_World` fails with `Unknown type 'Transport'` (tested). Hook `CarScript`/`BoatScript` (and `MotorbikeScript`) instead.
- A string built with `"x" + (bool expression)` crashed a 1.29 server during World compile (no script error, just a crash dump). Use `bool.ToString()`.

## Module System

Expansion is split into independent modules:
| Module | Workshop ID | Purpose |
|--------|-------------|---------|
| Core | 2291785308 | Base framework |
| Scripts | 2116151222 | All scripting |
| Market | Included | Trading/economy |
| Quests | Included | Quest system |
| AI | Included | AI patrols/guards |
| Basebuilding | Included | Territory/building |
| Vehicles | Included | Extended vehicles |

## Market System

### Configuration Files
- `ExpansionMarketSettings.json` - Global market settings
- `ExpansionMarketTraders/` - Individual trader configs
- `ExpansionMarketCategories/` - Item category definitions

### Trader Setup
```json
// ExpansionMarketTraders/MyTrader.json
{
    "TraderName": "General Store",
    "TraderIcon": "Deliver",
    "Currencies": ["ExpansionMoneyDollar"],
    "Items": [
        {
            "ClassName": "BandageDressing",
            "MaxPriceThreshold": 50,
            "MinPriceThreshold": 10,
            "SellPricePercent": 50,
            "MaxStockThreshold": 100,
            "MinStockThreshold": 1,
            "QuantityPercent": -1,
            "SpawnAttachments": [],
            "Variants": []
        }
    ]
}
```

### Market API
```c
// Get market module
ExpansionMarketModule marketModule = ExpansionMarketModule.Cast(
    CF_ModuleCoreManager.Get(ExpansionMarketModule));

// Check item price
int buyPrice = marketModule.GetBuyPrice("BandageDressing");
int sellPrice = marketModule.GetSellPrice("BandageDressing");

// Player money (via Expansion banking)
int balance = player.GetMoney();
```

## Quest System

### Quest Types
| Objective Type | Description |
|---------------|-------------|
| `TRAVEL` | Go to location |
| `COLLECT` | Collect items |
| `DELIVERY` | Deliver items to NPC |
| `TARGET` | Kill specific targets |
| `AIPATROL` | Kill AI patrol |
| `AICCAMP` | Clear AI camp |
| `TREASUREHUNT` | Find treasure |
| `ACTION` | Custom scripted action |

### Quest Configuration
```json
// ExpansionQuests/MyQuest.json
{
    "ID": 1001,
    "Title": "Supply Run",
    "Description": "Collect medical supplies",
    "ObjectiveType": "COLLECT",
    "Objectives": [
        {
            "ClassName": "BandageDressing",
            "Amount": 5
        }
    ],
    "Rewards": [
        {
            "ClassName": "ExpansionMoneyDollar",
            "Amount": 100
        }
    ],
    "PreQuest": -1,
    "Repeatable": true,
    "CooldownTime": 3600
}
```

### Quest Implementation (3 Phases)
1. **Define objectives** in JSON config
2. **Create NPC** with quest giver settings
3. **Register quest** in ExpansionQuestSettings.json

## AI System

### AI Patrol Setup
```json
// ExpansionAIPatrols/MyPatrol.json
{
    "Name": "Military Patrol",
    "Faction": "East",
    "LoadoutFile": "MilitaryLoadout",
    "NumberOfAI": 4,
    "Waypoints": [
        {"Position": [3456.7, 0, 8901.2]},
        {"Position": [3500.0, 0, 8950.0]},
        {"Position": [3450.0, 0, 9000.0]}
    ],
    "Behaviour": "PATROL",
    "Speed": "JOG",
    "RespawnTime": 1800,
    "DespawnTime": 300
}
```

### AI Settings
```json
// ExpansionAISettings.json
{
    "Enabled": true,
    "MaxRecruitableAI": 5,       // NEW in 1.9.41
    "LootDropOnDeath": true,
    "AccuracyMin": 0.3,
    "AccuracyMax": 0.7,
    "ThreatRange": 150
}
```

### AI FSM Behaviors
| Behavior | Description |
|----------|-------------|
| `PATROL` | Walk between waypoints |
| `GUARD` | Guard a position |
| `FOLLOW` | Follow a target |
| `IDLE` | Stand in place |

## Basebuilding / Territory

### Territory Setup
```json
// ExpansionTerritorySettings.json
{
    "Enabled": true,
    "TerritorySize": 150,
    "MaxMembersPerTerritory": 10,
    "MaxTerritoriesPerPlayer": 1,
    "EnableCodeLocks": true,
    "EnableFlagMenu": true
}
```

### Building Kits
- Territory Flag Kit (establishes territory)
- Wooden Floor/Wall/Roof Kits
- Metal variants for upgrades
- Code Lock Kit (security)

## Vehicle Extensions

Expansion adds helicopters, boats, bikes, and more with custom physics.

### Key Settings
```json
// ExpansionVehicleSettings.json
{
    "VehicleSyncRate": 10,
    "OverrideClientWeaponFiring": false,    // NEW in 1.9.48
    "RecreateWeaponNetworkRepresentation": false  // NEW in 1.9.48
}
```

## Persistence Pattern (3-Phase)

All Expansion data follows this save/load pattern:

```c
// Phase 1: OnStoreSave (server shutdown/autosave)
override void OnStoreSave(ParamsWriteContext ctx)
{
    super.OnStoreSave(ctx);
    ctx.Write(m_Data);
}

// Phase 2: OnStoreLoad (server startup)
override bool OnStoreLoad(ParamsReadContext ctx, int version)
{
    if (!super.OnStoreLoad(ctx, version)) return false;
    if (!ctx.Read(m_Data)) return false;
    return true;
}

// Phase 3: AfterStoreLoad (post-load initialization)
override void AfterStoreLoad()
{
    super.AfterStoreLoad();
    // Rebuild runtime state from loaded data
}
```

## 1.28 Expansion Notes

- **1.9.28**: Animation graph updated, CTD workarounds for `ProcessDirectDamage` and fog settings
- **1.9.30**: Dynamic physics disabled for items on contact (vanilla bug T192415)
- **1.9.47**: `GetGame()` replaced with `g_Game` across all mods
- **1.9.48**: `SurfaceRoadY(3D)` replaced with `GetSurface` NoWait for performance

### Known Issues
- Vehicle winching doesn't work properly
- Vehicle restore/uncover while standing on it may cause fall-through
