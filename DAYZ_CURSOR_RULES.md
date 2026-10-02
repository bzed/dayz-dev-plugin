# DayZ Enforce Script Development Rules

> For Cursor, Windsurf, and other AI coding assistants.
> Target: DayZ 1.29 (v1.29.163709, stable) and 1.30 (v1.30.164014, experimental; stable Oct 15, 2026), 1.28 notes kept

## Language: Enforce Script

DayZ uses **Enforce Script**, a C-like language. Key differences from C/C#/C++:
- No namespaces, no exceptions (try/catch), no operator overloading
- Single inheritance only, `modded class` for injection
- `ref` keyword for member variables only (NOT function params)
- Garbage collected with optional reference counting via `Managed`
- `autoptr` for scope-based cleanup
- Built-in `vector` type (3x float), `array<T>`, `set<T>`, `map<K,V>`

## Critical Rules

### NEVER DO
- Use C# syntax (`player.GetComponent<>()`, `using`, `namespace`)
- Use C++ syntax (`std::`, `template<>`, `nullptr`)
- Invent class names or methods that don't exist
- Use `ref` in function parameters, returns, or local variables
- Add `: ParentClass` inheritance to `modded class` (already inherits)
- Use `delete` keyword (null the reference instead; `delete` can segfault)
- Trust `GetGame().IsClient()` during init (returns FALSE)
- Skip null checks on `Cast<>`, `GetInventory()`, `GetIdentity()`
- Leave empty `#ifdef`/`#endif` blocks (causes segfaults)
- Write files outside `$profile:`, `$saves:` or `$mission:`; use backslashes in paths; pass `$`-placeholder paths to `FindFile` (broken on 1.30)
- Create methods with more than 16 parameters
- Compare against `int.MIN` (`1 < int.MIN` returns TRUE - known bug)

### ALWAYS DO
- Use `!GetGame().IsDedicatedServer()` for client checks during init
- Null-check every `Cast<>` result before use
- Call `super.Method()` in overrides
- Use `SetSynchDirty()` after changing NetSync variables
- Check `GetGame().IsServer()` before gameplay logic
- Parenthesize bitwise operations: `(flags & FLAG) == FLAG`
- Assign getter results to local var before `foreach`
- Use `g_Game` instead of `GetGame()` (1.29: `GetGame()` is only a wrapper returning `g_Game`)

## Mod Structure
```
@MyMod/Addons/MyMod/
├── config.cpp              # CfgPatches, CfgMods, CfgVehicles
├── $PREFIX$                # Addon prefix
├── scripts/
│   ├── config.cpp          # Script module registration
│   ├── 3_Game/             # Available everywhere
│   ├── 4_World/            # Entities, items, actions
│   └── 5_Mission/          # HUD, menus, mission logic
└── data/                   # Models, textures
```

## Script Module Access
- `5_Mission` can access `4_World` and `3_Game`
- `4_World` can access `3_Game`
- `3_Game` cannot access `4_World` or `5_Mission`

## Common Patterns

### Modded Class
```c
modded class PlayerBase
{
    override void SetActions(out TInputActionMap InputActionMap)
    {
        super.SetActions(InputActionMap);
        AddAction(MyAction, InputActionMap);
    }
}
```

### RPC (Vanilla)
```c
ScriptRPC rpc = new ScriptRPC();
rpc.Write(data);
rpc.Send(target, ERPCs.RPC_USER_ACTION_MESSAGE, true, identity);
```

### RPC (CF)
```c
GetRPCManager().AddRPC("MyMod", "MyHandler", this, SingleplayerExecutionType.Both);
GetRPCManager().SendRPC("MyMod", "MyHandler", new Param1<string>("data"), true, identity);
```

### Net Sync
```c
RegisterNetSyncVariableInt("m_Var", 0, 100);
// After changing: SetSynchDirty();
// Client receives: OnVariablesSynchronized()
```

### Null-Safe Item Creation
```c
PlayerBase player = PlayerBase.Cast(GetGame().GetPlayer());
if (player && player.GetInventory())
{
    EntityAI item = player.GetInventory().CreateInInventory("AKM");
    if (item)
    {
        item.SetHealth("", "", 100);
    }
}
```

## Documentation Sources
- Script API (latest, 1.29): https://diff.yadz.app/ (`api.json`, `classes/<Name>/`, `changelog/`)
- Script Diff: https://github.com/BohemiaInteractive/DayZ-Script-Diff
- BI Wiki: https://community.bistudio.com/wiki/DayZ:Enforce_Script_Syntax
- CF Docs: https://github.com/Arkensor/DayZ-CommunityFramework
- Expansion Wiki: https://github.com/salutesh/DayZ-Expansion-Scripts/wiki
- Server Config: https://dzconfig.com/wiki/

## 1.30 Changes (experimental; stable Oct 15, 2026) - target 1.29 AND 1.30
Verified on 1.29.163709 and 1.30.164014 experimental servers. Details: `compatibility/version-130.md`.
1. **Version define**: engine defines `DAYZ_1_29` or `DAYZ_1_30` (only the current one). Old code under `#ifdef DAYZ_1_29`, new code in `#else`; one PBO loads on both
2. **`FindFile` ignores `$profile:`/`$mission:`/`$storage:`/`$saves:`** on 1.30 (searches the server root instead) - wrap patterns with `compatibility/YOURMOD_FindFilePath.c`; other file functions still accept placeholders
3. **Forward slashes in all paths** - backslashes break `FindFile` on 1.30
4. **`ProcessVariables()`** → `ProcessVariables(float elapsedTime)`; **`OnCEUpdate()` is never called** → `OnCEIterate(float currentTime, float elapsedTime)`
5. **Car lights**: `CreateFrontLight/CreateRearLight` no longer called → register `VehicleLightProfile*` via `m_LightsComponent.RegisterLight`; `ToggleHeadlights()` removed → `LightToggle()`
6. **Inventory**: `*TakeEntityToCargo`/`*TakeEntityAsAttachment` obsolete → `*TakeEntityToTarget*` (exists in 1.29: switch now)
7. **Construction** split into `ConstructionBase`; `SetParent(EntityAI)`; `CombinationLock` signatures changed
8. **`ERPCs`** values shifted - never use raw ints
9. Experimental is a diag build (`DIAG_DEVELOPER`, `BUILD_EXPERIMENTAL`) - never use those as "is 1.30"

## 1.29 Breaking Changes
1. **`GetGame()`** is now a script function `DayZGame GetGame() { return g_Game; }` - use `g_Game`
2. **`ActiveState` enum reordered**: `INACTIVE=0, ACTIVE=1, ALWAYS_ACTIVE=2` (was `ACTIVE, INACTIVE, ...`) - never use raw ints
3. **Vehicle headlights native**: `CarScript.m_HeadlightsOn` removed; use `Transport.LightIsOn/LightOn/LightOff/LightToggle`, override `OnBeforeLightOn()`
4. **Sleeping physics bodies** no longer tick `EOnSimulate`/`EOnPostSimulate`
5. **Junctures**: `AddActionJuncture`/`AddInventoryJuncture(Ex)` gained `Managed userData = null`
6. **`InventoryLocationType.TEMP`** added (client-side desync limbo)
7. **StaminaHandler** reworked (move/state reconciliation); `GetCooldownTimer` removed, `DepleteStamina`/`OnRPC` obsolete
8. **Removed**: `DayZPlayerImplement.GetNVEntityAttached()` - use `GetCachedEquipment()`; `CGame.Gizmo*` obsolete - use `GetGizmoApi()`
9. **Terrain**: WRP must be binarized with 1.29 tools

## 1.28 Breaking Changes
1. Vehicle brake values must be doubled
2. Contact class: `dMaterial` -> `SurfaceProperties`, removed MaterialIndex/Index
3. `PhysicsGeomDef.MaterialName` now takes .bisurf or #CfgSurfaces
4. 16-parameter method limit enforced
5. `sealed` keyword prevents inheritance
6. Storage wipe recommended for modded servers (horticulture)
