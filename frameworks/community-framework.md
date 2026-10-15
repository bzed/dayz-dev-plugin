# Community Framework (CF)

> **CF:** Steam Workshop **1559212036**, version **1.5.9**, the build for DayZ **1.30** (stable since Oct 15, 2026)
> **GitHub:** https://github.com/Arkensor/DayZ-CommunityFramework
> **Minimum for 1.28:** CF 1.5.7
> **CF-Test (1625463737) is obsolete:** the Workshop CF 1.5.9 PBOs (`scripts`, `gui`, `legacy`) are byte-identical to the last CF-Test build (checked 2026-10-14).
> **Source of truth:** the CF-Test build was unpacked, diffed against CF 1.5.8 and booted with a test mod on
> a 1.30.164014 pre-release server (Oct 3, 2026). Statements marked **(tested)** were observed there.

## Which CF to use

Use the regular **CF 1.5.9 or newer** (1559212036) for 1.30. One CF dependency: `JM_CF_Scripts`.
Do not subscribe to or depend on **CF-Test**; if a launcher or server still has it, replace it with CF (same `CfgPatches`
class `JM_CF_Scripts` and `CfgMods` class `JM_CommunityFramework`, so `requiredAddons[] = {"DZ_Data", "JM_CF_Scripts"};` is unchanged).
Load only **one** of the two: both declare `JM_CF_Scripts` and conflict. COT works the same: the current Community Online Tools
(1564026768) already calls `CF.FindFileEx`, so **COT-Test is not needed either**.

- **CF 1.5.9 loads on 1.30 (tested, as CF-Test).** The same unmodified PBO compiled on 1.30.164014,
  with no `SCRIPT (E)` lines from CF itself. 1.30-only code in it is behind `#ifndef DAYZ_1_29`.
  (The `config.cpp` `version = "1.5.8"` string was never updated; don't test for the version string.)
- **What 1.5.9 changes compared with CF 1.5.8** (unpacked-source diff, 19 files):
  - **New `CF.ResolvePath` and `CF.FindFileEx`** for DZEXP-134, see [FindFile](#cffindfileex-and-cfresolvepath).
  - **`MotorbikeScript` gets ModStorage** (`#ifndef DAYZ_1_29`; the motorbike is new in 1.30).
  - **ModStorage hardening:** `AdvancedCommunication`, `AnimalBase`, `BuildingBase` and `ZombieBase` create their
    `CF_ModStorageObject` lazily, and `CF_ModStorageObject` rejects a corrupt header (CF version too new or more
    than 256 mods) with an error instead of reading garbage.
  - **Input bindings** keep a persistent `UAIDWrapper` (`GetPersistentWrapper()`) instead of an `int` input ID
    (`CF_InputBinding.m_InputID` is gone; use `m_InputWrapper`).
  - **`JMAnimRegister`**: the legacy `Register(pType)` is now deprecated and empty; `OnRegisterCustom`/`RegisterCustom`
    lose their `pBehavior` argument. `ManBase/DayZPlayerCameras.c` was removed.
  - **Strings:** `CF_String.LastIndexOf` is `[Obsolete]` (use `string.LastIndexOf`); `Replace` and `Base64Stream` log an
    `Error()` when a `Substring` would exceed 8191 characters; `ConfigReader` now accepts `-` in names.
- **Experimental servers are diag builds** (tested on the 1.30 pre-release), so any `Error()` inside CF (for example "Could not determine mission
  folder") shows up as a `Virtual Machine Exception` there (see `compatibility/version-130.md`).

### Requirements for 1.30 servers

Announced with **DayZ Expansion 1.9.74** (for DayZ 1.30):

- Use **CF 1.5.9+** (and the current COT if you use COT). Older CF/COT lack the FindFile workaround.
- **The server profile folder must be inside the server executable's folder** (a symlink works too). Otherwise the
  game cannot find it, because of the vanilla 1.30 `FindFile` bug (DZEXP-134): the workaround resolves `$profile:`
  to a path relative to the server folder and only keeps the last component of `-profiles=`.
  ```sh
  ln -s /data/dayz/profile /srv/dayz/server/profile   # real profile elsewhere
  ./DayZServer -profiles=profile ...                  # never -profiles=/data/dayz/profile
  ```
- Mods without a CF dependency get the same behavior from `compatibility/YOURMOD_FindFilePath.c`, so with or without CF
  the profile folder rule is identical.

### Starting a 1.30 server with CF

1. Load **CF** like any mod: `-mod=@CF` (client-side) with its `.bikey` (`keys/Jacob_Mango_V3.bikey`) in the
   server's `keys/`. For local tests symlink the item into your own server tree (`testing/local-server.md`).
2. Start the server with **`-profiles=<dir>`** and **`-mission=mpmissions/<mission folder>`**. CF's
   path resolution reads both **(tested)**. Without `-mission`, CF falls back to the `Missions DayZ template`
   from `-config=`, which is only the folder name (`dayzOffline.chernarusplus`, no `mpmissions/`), so `$mission:`
   and `$storage:` resolve to a folder that doesn't exist: `FindFileEx` returns nothing and the diag build prints
   a `Virtual Machine Exception`. With `-mission=mpmissions/dayzOffline.chernarusplus` both worked.
3. CF needs a writable `$profile:` (it creates `cf_findfile_dz130_test` there once) and `-profiles` must
   be a folder under the game directory (it only keeps the last path component; see the requirement above). It logs
   "Profile folder X does not exist inside game directory" otherwise. Mission folder order: `GetMissionPath()`, `-mission=`,
   `-config=` template, world-name guess.

## Overview

Community Framework provides essential modding utilities:
- **RPCManager** - Named cross-mod RPC system
- **Modules** - Event-driven module registration
- **NetworkedVariables** - Easy state synchronization
- **ModStorage** - Per-entity persistent storage
- **TypeConverters** - Type conversion utilities
- **NotificationSystem** - In-game notifications
- **Surface Info** - Surface type queries

## Script Structure
```
JM/CF/
  Scripts/
    config.cpp
    3_Game/
      CommunityFramework/
        CommunityFramework.c        # Core framework
        RPC/
          RPCManager.c              # Cross-mod RPC
        Game/
          DayZGame.c                # Modded DayZGame
        Notification/
          NotificationSystem.c      # Notifications
    4_World/
      CommunityFramework/
        Module/                     # World-level modules
    5_Mission/
      CommunityFramework/
        Module/                     # Mission-level modules
```

## RPCManager

### Registration
```c
// Register in your class constructor or init
GetRPCManager().AddRPC(
    "MyModName",                        // Namespace (your mod name)
    "RPC_FunctionName",                 // RPC name (must match handler method)
    this,                               // Handler object
    SingleplayerExecutionType.Both      // Singleplayer behavior (default: Server)
);
```

The handler is a method of `this` named exactly like the RPC. `AddRPC` returns `bool`. The enum
`SingleplayerExecutionType` exists in CF 1.5.8; the old misspelling `SingeplayerExecutionType` is still declared
too (values `Server = 0`, `Client`, `Both`).

### SingleplayerExecutionType
| Value | Behavior |
|-------|----------|
| `Both` | Runs on both client and server in SP |
| `Client` | Client-side only in SP |
| `Server` | Server-side only in SP (default) |

### Sending
```c
// To specific client (from server)
GetRPCManager().SendRPC("MyMod", "RPC_Name",
    new Param1<string>("data"),
    true,                              // Guaranteed delivery
    targetPlayer.GetIdentity());       // Target client

// To server (from client)
GetRPCManager().SendRPC("MyMod", "RPC_Name",
    new Param1<int>(42),
    true,
    null);                             // null = server

// Broadcast to all clients: identity null from the server
GetRPCManager().SendRPC("MyMod", "RPC_Name",
    new Param1<string>("broadcast"),
    true,
    null);
```

Signature: `SendRPC(string modName, string funcName, Param params = NULL, bool guaranteed = false, PlayerIdentity sendToIdentity = NULL, Object sendToTarget = NULL)`.
`SendRPCs(..., array<ref Param> params, ...)` sends several param objects in one go (it does not support
`SingleplayerExecutionType.Both`). There is no `VSendRPC` in CF 1.5.8.


### Handler Pattern
```c
void RPC_MyHandler(CallType type, ParamsReadContext ctx, PlayerIdentity sender, Object target)
{
    // Read parameters (MUST match what was sent)
    Param2<string, int> data;
    if (!ctx.Read(data)) return;

    string name = data.param1;
    int value = data.param2;

    if (type == CallType.Server)
    {
        // Running on server
        if (!sender) return;  // Validate sender
        // Process server-side
    }
    else if (type == CallType.Client)
    {
        // Running on client
        // Update UI, effects, etc.
    }
}
```

## CF Modules

### Registration
```c
[CF_RegisterModule(MyModule)]
class MyModule : CF_ModuleWorld
{
    // Module is automatically instantiated and registered
}
```

Get the instance with `CF_Modules<MyModule>.Get()`. Module classes are `CF_ModuleGame` (3_Game, adds
RPC/input bindings/networked variables), `CF_ModuleWorld` (4_World, adds the client lifecycle events) and
`CF_ModuleCore`; `CF_Module` is a typedef of `CF_ModuleGame`.

### Key Events
**A module only receives the events it enables.** Call the matching `Enable...()` in `OnInit()`
(`EnableUpdate()`, `EnableMissionStart()`, `EnableMissionFinish()`, `EnableMissionLoaded()`, `EnableSettingsChanged()`,
`EnableWorldCleanup()`, ... and for `CF_ModuleWorld` `EnableClientNew()`, `EnableClientReady()`,
`EnableClientDisconnect()`, `EnableInvokeConnect()`, ...). An override without its `Enable` call is never invoked.
```c
class MyModule : CF_ModuleWorld
{
    override void OnInit()
    {
        super.OnInit();
        EnableUpdate();
        EnableMissionStart();
        EnableClientReady();
        // Module initialization - register RPCs, load config
    }

    override void OnUpdate(Class sender, CF_EventArgs args)
    {
        // Per-frame update; args is a CF_EventUpdateArgs
        CF_EventUpdateArgs update = CF_EventUpdateArgs.Cast(args);
        float dt = update.DeltaTime;
    }

    override void OnMissionStart(Class sender, CF_EventArgs args)
    {
        // Mission started
    }

    override void OnMissionFinish(Class sender, CF_EventArgs args)
    {
        // Mission ending - save data
    }

    override void OnMissionLoaded(Class sender, CF_EventArgs args)
    {
        // Mission fully loaded
    }

    override void OnClientReady(Class sender, CF_EventArgs args)
    {
        // Client fully loaded and ready
    }

    override void OnClientDisconnect(Class sender, CF_EventArgs args)
    {
        // Client disconnecting
    }

    override void OnClientNew(Class sender, CF_EventArgs args)
    {
        // New client connected
    }

    override void OnClientRespawn(Class sender, CF_EventArgs args)
    {
        // Client respawning
    }
}
```

## ModStorage (CF 1.5.5+)

Per-entity persistent storage that survives server restarts and is namespaced per mod, so several mods can
store data on the same entity without breaking each other's `OnStoreLoad` order. Don't override vanilla
`OnStoreSave`/`OnStoreLoad` for this: CF already does, and writes a header the vanilla version doesn't know.
Override the CF hooks instead. They exist on `ItemBase`, `AdvancedCommunication`, `AnimalBase`, `BuildingBase`, `ZombieBase`
(and `MotorbikeScript` in CF 1.5.9 / 1.30) and are keyed by your `CfgMods` class name:

```c
modded class KitBase // extends from ItemBase
{
    protected int m_MyMod_Value;

    override void CF_OnStoreSave(CF_ModStorageMap storage)
    {
        super.CF_OnStoreSave(storage);

        auto ctx = storage["MyModClassName"];  // the class name from your CfgMods
        if (!ctx) return;
        ctx.Write(m_MyMod_Value);
    }

    override bool CF_OnStoreLoad(CF_ModStorageMap storage)
    {
        if (!super.CF_OnStoreLoad(storage)) return false;

        auto ctx = storage["MyModClassName"];
        if (!ctx) return true;                 // nothing saved by this mod yet
        if (!ctx.Read(m_MyMod_Value)) return false;
        // ctx.GetVersion() returns the mod's `storageVersion` for conditional reads
        return true;
    }
}
```

- The mod version used by `ctx.GetVersion()` is `storageVersion` in your `CfgMods` class.
- **Note (CF 1.5.7+):** ModStorage no longer requires a custom class inheriting from `ModStructure`.
- **CF 1.5.8 vs 1.5.9:** 1.5.9 adds `MotorbikeScript` (1.30) and rejects a corrupt header
  (`Corrupt modstorage header, unsupported CF version ... or too many mods`) by returning `false` from the load.
  A storage written by CF 1.5.9 on DayZ 1.30 should be treated as not loadable by older servers, as for vanilla
  (`compatibility/version-130.md`, persistence).

## NetworkedVariables

Modules sync member variables by **name**, like vanilla `RegisterNetSyncVariable*`, but through a `CF_ModuleGame`
(there is no `CF_NetworkedVariable<T>` wrapper class):

```c
class MyModule : CF_ModuleWorld
{
    int m_Score;
    string m_Message;

    override void OnInit()
    {
        super.OnInit();
        RegisterNetSyncVariable("m_Score");      // only call this in OnInit
        RegisterNetSyncVariable("m_Message");
    }

    void SetScore(int score)                      // server
    {
        m_Score = score;
        SetSynchDirty();                          // sends all registered variables to every client
    }

    override void OnVariablesSynchronized(Class sender, CF_EventArgs args)   // client
    {
        // m_Score / m_Message are now updated
    }
}
```

**Limits:** at most 256 registered variables per module; `"a.b.c"` registers a member of a nested class, with a
maximum nesting depth (`CF_NetworkVariable.MAX_DEPTH`). Only the dedicated server sends; in offline mode
`OnVariablesSynchronized` is called directly. Sync uses RPC id 435022.

## NotificationSystem

CF extends vanilla `NotificationSystem` with localised, colourable notifications:

```c
// Server: sendTo = player's identity, or null for everyone. Client: shows it locally.
NotificationSystem.Create(
    new StringLocaliser("Title"), new StringLocaliser("Message %1", "text"),
    "set:dayz_gui image:icon_info", ARGB(255, 0, 255, 0), 5, player.GetIdentity());
```
Signature: `Create(StringLocaliser title, StringLocaliser text, string icon, int color, float time = 3, PlayerIdentity sendTo = NULL)`
(`CreateNotification` is the same). Vanilla's `AddNotification(NotificationType, ...)` still works for the stock
types.

## TypeConverters

`CF_TypeConverter.Get(typename)` returns the registered `CF_TypeConverterBase` for a type (int, float, bool,
string, vector, Class, Managed, ...). They are used by CF's config/XML/expression code to read and write values from
text. There are no static `IntToString`/`StringToInt` helpers in CF 1.5.8; use the vanilla `ToString()`/`ToInt()`.

## CF.FindFileEx and CF.ResolvePath

DayZ 1.30's `FindFile` ignores `$profile:`/`$mission:`/`$saves:` (DZEXP-134, not fixed at release).
CF adds `CF.ResolvePath` (prefixed path -> real path) and `CF.FindFileEx`, a drop-in `FindFile` wrapper that
tests for the bug and resolves the path only when needed. Use it for every `FindFile` call. **Needs CF 1.5.9+; CF 1.5.8 does not have it.**
Signature: `CF.FindFileEx(string pattern, out string fileName, out FileAttr attr, FindFileFlags flags)`
(`flags` has no default).

Tested with CF 1.5.9 (as CF-Test) on a 1.30 pre-release server (first call after the mission started, `-profiles=profiles -mission=mpmissions/dayzOffline.chernarusplus`):

| Pattern | Result on 1.30 |
|---|---|
| `$profile:cfp/*.json` (also with `\`) | found (resolved) |
| `$mission:cfg*.json` | found only with `-mission=`; otherwise nothing + VM exception |
| `$storage:d*` | found (`data`) once `storage_1` exists |
| `$saves:*` | nothing (resolved to `<profile>/Users/Server/...`) |

It tests once and resolves
only if `FindFile` is broken (on a fixed engine it passes the pattern through apart from the slash fix). `CF.ResolvePath` is public too.
See `compatibility/version-130.md` section 2.

## config.cpp Integration

```cpp
class CfgPatches
{
    class MyMod
    {
        requiredAddons[] = {"DZ_Data", "JM_CF_Scripts"};
    };
};
```

## CF 1.5.7+ Changes (1.28 Compatible)
- ModStorage simplified (no ModStructure needed)
- Fixed file state tracking on entity load
- Millisecond logging timestamps
- Non-ASCII character handling fixes

## CF 1.5.8
- `CF_Byte::ToHex` renamed to `CF_ToHex`
- No longer creating new `CF_EventUpdateArgs` each OnUpdate (performance)
- `GetGame()` -> `g_Game` optimization recommended
- Defines exported by `CfgMods` (usable in `#ifdef`): `CF_MODULES`, `CF_MODSTORAGE`, `CF_SURFACES`, `CF_EXPRESSION`,
  `CF_ONUPDATE_RATE_LIMIT`, `CF_LOG_TIMESTAMP`, ... Use `#ifdef CF_MODULES` to detect CF without a hard dependency.

## CF 1.5.9 (DayZ 1.30)
See [Which CF to use](#which-cf-to-use): `CF.FindFileEx`/`CF.ResolvePath`, `MotorbikeScript`
ModStorage, corrupt-header check, persistent input wrappers.
