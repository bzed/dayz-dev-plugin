# Best Practices, Anti-Patterns and Common Patterns

Quick reference for Enforce Script style, memory and null safety, mod folder layout, and the usual DayZ
idioms (modded class, RPC, net sync variables). For the language itself see `enforce-script.md`.

## Enforce Script Rules
| Rule | Why |
|------|-----|
| Use `!GetGame().IsDedicatedServer()` for client check | `IsClient()` returns FALSE during init |
| Assign getter results to local var before foreach | `foreach` on inline getter returns fails |
| Always parenthesize bitwise ops: `(a & b) == b` | Bitwise ops have lower precedence than comparisons |
| Use `ref` ONLY for member variables | `ref` in function params is WRONG |
| Check last file before reported error location | Compiler errors often point to wrong file |
| Never leave empty preprocessor blocks | Can cause segfaults |

## Memory Management Rules
| Rule | Why |
|------|-----|
| `ref` for member variables only | Controls reference lifetime |
| Never `delete` manually | Enforce Script uses GC |
| Inherit from `Managed` for ref counting | Enables `ref`/`autoptr` usage |
| `autoptr` auto-deletes when scope exits | Use for temporary owned references |

## Null Safety Rules
| Rule | Example |
|------|---------|
| Always check `Cast<>` results | `PlayerBase p = PlayerBase.Cast(entity); if (p) {...}` |
| Always check `GetInventory()` | `if (player.GetInventory()) {...}` |
| Always check `GetIdentity()` | `if (player.GetIdentity()) {...}` |
| Always check `GetGame().GetPlayer()` | Can be null during init/cleanup |

## Security Rules
| Rule | Reason |
|------|--------|
| Validate on server side | Client can be tampered |
| Check `GetGame().IsServer()` before gameplay logic | Prevent client-side exploitation |
| Use RPC callbacks, not direct events | Prevent event spoofing |
| Validate player identity on server RPCs | Prevent impersonation |

## Mod Structure
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
| `Print(longString)` with 240+ chars | Script log cuts at 255 incl. a 16-char prefix, silently. Keep messages short or chunk them (`scripting/enforce-script.md`, Logging) |
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
