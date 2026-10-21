# DayZ 1.30 Compatibility Guide

> **Status (Oct 15, 2026):** 1.30 is the **PC Stable** release. No experimental branch is needed to target it.
> **Update 1.30.164200 (build 25963285):** a minor update changed base-building APIs, see the last table of section 3.
> **Source of truth:** script diff of the previous stable (1.29.163709) against 1.30.164014 (the last pre-release
> build checked; local `dayz-sources` git, tags `1.29` / `1.30`) plus test mods booted on a 1.30.164014.27
> dedicated server (Linux, Oct 2, 2026). Statements marked **(tested)** were observed there. The stable
> release build number may differ from 164014: re-check **(tested)** claims on it when something looks off.
> DZEXP-134 (the `FindFile` bug, section 2) was not fixed at release, so use `CF.FindFileEx`.
> Remote references (diff.yadz.app, DayZ-Script-Diff) may lag behind: prefer a local copy of the 1.30 scripts.

Diff previous stable → 1.30, scripts only: 837 files, +53k/−12k lines. New content (Nasdara map, sandstorms,
motorbikes, code locks, bunker radio broadcasts, rebuilding of map structures) drives most of it.
The sections below cover what affects mods.

## Contents
1. [Version define: `DAYZ_1_30`](#1-version-define)
2. [File paths: `$profile:`, `$mission:`, forward slashes, `FindFile`](#2-file-paths-and-findfile)
3. [Compile breakers (overrides and calls)](#3-compile-breakers)
4. [Silent breakers (compile fine, behave differently)](#4-silent-breakers)
5. [Obsolete in 1.30 (warnings)](#5-obsolete-in-130)
6. [New APIs](#6-new-apis)
7. [Experimental builds](#7-experimental-builds)
8. [Review checklist](#8-review-checklist)

---

## 1. Version define

**The engine defines the version (tested).** The script-module `defines:` line in `script_*.log` of a 1.30
server contains `DAYZ_1_30, SERVER, ...`. Only the current version's define exists: 1.30 does **not** define
`DAYZ_1_29`, and 1.29 did not define `DAYZ_1_28`.

- You normally need no `#ifdef` for the version: write plain 1.30 code.
- A mod that must still load on 1.29 or older servers puts the *old* code under `#ifdef DAYZ_1_29` and the new
  code in `#else`, so the new code stays the default on 1.31+. `#ifdef DAYZ_1_30` would silently drop code again
  on 1.31.
- Runtime version string: `string v; g_Game.GetVersion(v);` gives e.g. `"1.30.164014.27"` **(tested)**. Use it for logging.
  It cannot select code that would not compile, so use the define for that.
- Your own defines work too: `defines[] = {"MYMOD"};` in `CfgMods` → `#ifdef MYMOD` **(tested)**.
- **Do not use `BUILD_EXPERIMENTAL`/`DIAG_DEVELOPER` to mean "1.30".** They are only defined on experimental diag builds
  and are gone on stable.

## 2. File paths and FindFile

**What changed (tested, server side):** on 1.30, `FindFile()` ignores the `$profile:`, `$mission:`,
`$storage:` and `$saves:` placeholders. It returns **no error**, but silently lists the server's working
directory instead (`FindFile("$profile:*")` returned `DayZServer`, `addons`, `keys`, ...).
Backslash paths find nothing. BI tracks it as **DZEXP-134**. Cause (per the ticket): the script binding of `FindFile` still passes the
`FindFileFlags` value where the reworked native `FileSystemImpl::FindFirst` expects a file system index.
BI did not fix it for the 1.30 release, so mods must work around it.

> **Requirement for every 1.30 server (announced with DayZ Expansion 1.9.74): the profile folder
> (`-profiles=<dir>`) must be inside the server executable's folder; a symlink there also works.** The workaround
> (`CF.FindFileEx`, and our fallback helper) resolves `$profile:` to a path relative to the server folder, so a
> profile folder anywhere else is not found by the game: `FindFile` returns nothing, and the vanilla 1.30
> `FindFile` bug is the reason. An absolute `-profiles=/srv/dz/profile` is reduced to `profile` and looked up in
> the server folder. Same for `-mission=` / the mission folder and `-storage=`. Fix:
> `ln -s /srv/dz/profile <server folder>/profile` and start with `-profiles=profile`.
> Mods that use CF need **CF 1.5.9 or newer** (the regular Workshop CF contains the workaround; CF-Test and COT-Test are not needed; Expansion
> needs Dabs Framework on top; see `frameworks/expansion.md`). See `frameworks/community-framework.md`.

Results of the test matrix on 1.30:

| Operation | `$profile:` `$mission:` `$saves:` (either slash) | relative `profiles/x/` fwd slash | relative, backslash | absolute fwd slash | `$storage:` after the mission is running (see below) |
|---|---|---|---|---|---|
| `MakeDirectory`, `OpenFile` R/W, `FileExist`, `CopyFile`, `DeleteFile`, `JsonFileLoader` | ✅ | ✅* | ✅* | – | ✅ |
| `FindFile` | ❌ **wrong dir** | ✅ | ❌ | ✅ | ❌ |

\* writable on the pre-release (diag) server; that may be a `DEVELOPER`-build relaxation. Don't rely on it.

Consequences:
- **Keep using `$profile:` / `$mission:` / `$saves:` for every file function except `FindFile`.** `$storage:` works too, but only
  once the mission is running (next bullet).
- **`$storage:` is not available during mission start (tested, server side).** It becomes usable only after
  `MissionServer.OnMissionStart()` has returned (and `storage_<instanceId>` existed at boot):
  `FileExist`, `MakeDirectory`, `OpenFile` all returned false in the `MissionServer` constructor, `OnInit()` and
  both sides of `OnMissionStart()`, and true from the first `MissionServer.OnUpdate()` / `CallLater` tick
  (7-10 s later, after the mission init). Don't touch `$storage:` before that: wait for the first `OnUpdate` or a `CallLater`. On the **very
  first boot of an instance** (no `storage_1` yet) it stayed unavailable for the whole 60 s run, so fall back to the resolved path (`<mission folder>/storage_<instanceId>/`) when it is false.
  `FindFile("$storage:...")` does not work on 1.30 (DZEXP-134 again: `FileExist`
  true, `FindFile` returns no handle). The 1.30 build ignored a relative `-storage=<dir>` and kept the default
  folder; don't rely on `-storage` together with `$storage:`.
- **Use forward slashes in every path you build.** They work everywhere; backslashes
  break `FindFile` on 1.30. This includes paths assembled from parts (`dir + "/" + name`, not `"\\"`).
- **Script module paths in `CfgMods` need forward slashes too (tested, Linux server 1.30.164014).** With `files[] = {"MyMod\scripts\4_World"};` a 1.30 server loads the mod's config
  and shows its `CfgMods` defines, but compiles **none** of its scripts, and prints no error. The World
  module count stays at vanilla (2321 instead of 2321 + the mod's files). The
  fix is `files[] = {"MyMod/scripts/4_World"};`. The case of the folder name made no
  difference (`scripts` against a real `Scripts` folder loaded). Found in Haralds Armory (Workshop
  3325200572), whose five PBOs all used backslash paths. Windows servers were not tested. Check every
  `worldScriptModule`/`gameScriptModule`/`missionScriptModule` entry, also in a debinarized `config.bin`.
- **Replace every `FindFile` call with `CF.FindFileEx`** (Community Framework). It is a wrapper around
  `FindFile` that detects whether the bug is present and, if so, resolves the path with `CF.ResolvePath`,
  so it is a drop-in replacement, correct on 1.30 and after BI fixes the engine. It ships in
  **CF 1.5.9+** (Steam Workshop). Needs a CF dependency
  (`requiredAddons`/mod list). Reported by lava76 in DZEXP-134. Signature, read from CF 1.5.9 (Workshop 1559212036) source:
  `static FindFileHandle FindFileEx(string pattern, out string fileName, out FileAttr fileAttributes, FindFileFlags flags)`
  (same as `FindFile`, but `flags` has no default: always pass it).
  ```c
  string fileName;
  FileAttr attr;
  FindFileHandle h = CF.FindFileEx("$profile:YOURMOD/*.json", fileName, attr, FindFileFlags.ALL);
  ```
  Keep the loop, open-by-placeholder and `CloseFindFile` shape below unchanged.
- **Mods without a CF dependency**: wrap every `FindFile` pattern with the bundled fallback helper `compatibility/YOURMOD_FindFilePath.c`
  (rename `YOURMOD`, drop into `3_Game`). It is a port of CF's `FindFileEx`/`ResolvePath`: it flips slashes and
  tests once whether `FindFile` is broken and resolves `$profile:`/`$mission:`/`$storage:`/`$saves:` only if so **(helper tested on a 1.30.164014 server, same results as CF)**:
  ```c
  string fileName;
  FileAttr attr;
  FindFileHandle h = FindFile(YOURMOD_FindFilePath("$profile:YOURMOD/*.json"), fileName, attr, FindFileFlags.ALL);
  bool found = fileName != "";   // first match comes back in fileName; "" = nothing found
  while (found)
  {
      // fileName is a bare name: open it with the placeholder path, not the resolved one
      MyMod_Load("$profile:YOURMOD/" + fileName);
      found = FindNextFile(h, fileName, attr);
  }
  if (h)
      CloseFindFile(h);
  ```
  Enforce Script has no `do { } while`: it fails with `Can't find variable 'do'` (tested), so use this shape.
- How `CF.FindFileEx` works (CF 1.5.9 source): on 1.30 and later it writes `$profile:cf_findfile_dz130_test`
  once, tries `FindFile` on it and, if that fails, resolves every pattern with `CF.ResolvePath`. So a fixed
  engine needs no workaround, and it needs a writable `$profile:`. `CF.ResolvePath(path)` also flips
  backslashes and handles `$profile:`, `$saves:` (`<profile>/Users/Server`), `$mission:`, `$storage:`,
  `$currentdir:`; results are relative to the game dir, so `-profiles=` and the mission must be under it
  (absolute `-profiles=`/`-storage=` values are cut down to their last path component; it logs
  "Profile folder X does not exist inside game directory" when that fails).
  Mission folder comes from `g_Game.GetMissionPath()`, else `-mission=`, else `serverDZ.cfg` template via
  `-config=`, else a guess from the world name (`mpmissions/dayzOffline.<world>` etc.). Our fallback helper is a port of it (same one-time bug test, same
  folder reduction, `$saves:`, mission order, existence warning), so a mod with and without CF behaves the same. Differences on purpose: it
  uses `Print` instead of `ErrorEx` (a VM exception on diag builds), reads the `template="..."` line of `serverDZ.cfg` itself
  (vanilla has no `ConfigFile`) and adds the `mpmissions/` prefix CF's version misses.
- Resolution sources of the fallback helper (same as CF): `$profile:` ← `-profiles=` CLI param (required; a server started
  without it can't be resolved; absolute values keep only the last component, so the folder must be in the server folder),
  `$saves:` ← `<profile>/Users/Server`, `$mission:` ← folder of `g_Game.GetMissionPath()`, else `-mission=`, `$storage:` ←
  `-storage=<dir>` (same reduction) if given, else `<mission folder>`, plus `/storage_<instanceId>` (`serverDZ.cfg` `instanceId`, default 1).
  Tested: 1.30 with `-profiles=<absolute dir outside the server folder>` logs the "does not exist" warning and `FindFile` finds nothing, as with CF.
  `$saves:*` finds nothing on 1.30 (`<profile>/Users/Server` is missing there), also like CF.
  It prints a warning when the resolved folder does not exist.
- **`g_Game.GetMissionFolderPath()` returns `""`** on 1.30 servers (tested): vanilla's
  `SetMissionPath` only splits on `\`, but the engine passes `mpmissions/<mission>/mission.c`.
  Derive the folder from `GetMissionPath()` instead, as the helper does.
- The community gist `YOURMOD_FindFile_DZEXP134_Helper.c` (lava76) is **obsolete**; its author moved the
  logic into CF (`CF.ResolvePath`, `CF.FindFileEx`). Don't copy it (it also had bugs: a stray `)`,
  `"storage_%1"` instead of `%2`, a `serverDZ.cfg` parser tripping on the stock trailing comment).
- Mods that only *read a known file name* (`JsonFileLoader.LoadFile("$profile:MyMod/config.json")`) are
  unaffected. Mods that *enumerate* a directory (load all `*.json`, list saved loadouts, rotate logs)
  break silently: they find nothing, or the server root's files.
- Client side was not tested; assume the same `FindFile` behavior.

## 3. Compile breakers

Each of these stops the module from compiling on 1.30. On the pre-release server, a script compile failure
was followed by a **segfault** of the server (tested). A crash at boot is often a compile error, so read
`script_*.log` first.

### Override signature changes (tested where marked)
| Before 1.30 | 1.30 | Notes |
|---|---|---|
| `EntityAI/ItemBase.ProcessVariables()` **(tested)** | `ProcessVariables(float elapsedTime)` | error: "marked as override, but there is no function with this name" |
| `Construction.SetParent(BaseBuildingBase parent)` **(tested)** | `SetParent(EntityAI parent)` | `Construction` now extends `ConstructionBase : ConstructionBasic` |
| `Environment.ApplyWetnessToItem(ItemBase)` | `(ItemBase, EnvironmentEntityData itemAttributes = null)` | plus a private map overload |
| `Environment.ApplyDrynessToItemEx(ItemBase, EnvironmentDrynessData)` | adds `EnvironmentEntityData itemAttributes = null` | |
| `CombinationLock.SetCombination(int)` | `(int combination, bool setOtherSide = true)` | locks have an inside and outside now |
| `CombinationLock.DialNextNumber()` / `SetNextDial()` | `(int lockSide = FACING_OUTSIDE)` | |
| `CombinationLock.CheckLockedStateServer()` | `(bool insideLock = false)` | several lock methods are now `protected` |
| `ActionTargetsCursor.Update()` / `BuildFixedCursor()` | `Update(bool fullUpdate = true)` / `BuildFixedCursor(bool forceRebuild = true)` | UI mods |
| `MainMenuConsole/ServerBrowserTab.OnDLCChange(EDLCId)` | `OnDLCChange()` | |
| `ServerBrowserMenuNew.Play()` | `Play(bool warnAboutMissingDLC = true)` | |
| `CrashDebugData.SendData(PlayerBase)` | `SendData(DayZPlayer)` | |
| `ScriptConsole.RegisterTab(handler)` | `RegisterTab(int id, handler)` | admin tools that add console tabs |
| `BotGuardHasItemInHands.GuardCondition(HandEventBase)` | `GuardCondition(BotEventBase)` | |
| `HumanItemAccessor.OnItemInHandsChanged(bool)` | adds `bool pChangeAnimationInstance = true` | calls still compile |

Adding a parameter, even one with a default, changes the signature: the old override no longer compiles.

### Removed members (calls or overrides fail to compile)
| Removed in 1.30 | Use instead |
|---|---|
| `CarScript.ToggleHeadlights()` **(tested)** | `LightToggle()` (on `Transport`) |
| `CarScript.GenerateCarHornAINoise`, `CarHorn*ActionInput` | `VehicleHornComponent` (`Transport.GetVehicleHornComponent()`), `VehicleHornShort/LongActionInput`, `ActionVehicleHornShort/Long` |
| `CarScript.m_ForceUpdateLights` | – (`ForceUpdateLightsStart/End` obsolete, no replacement) |
| `EntityAI/ItemBase.m_ElapsedSinceLastUpdate`, `EntityAI.m_LastUpdatedTime` | `elapsedTime` parameter of `OnCEIterate`/`ProcessVariables` |
| `ItemBase.m_ItemActionOverrides` | `OverrideActionAnimation`/`SetActionAnimOverrides` now live on `EntityAI` |
| `AmmoTypesAPI.GetExplosionParticleID(ammo, surface)` | `AmmoTypesAPI.GetExplosiveEffectData(ammo, surface)` → `.m_ParticleID`, `.m_SoundSetName` |
| `Ammo_40mm_Explosive.ShootsExplosiveAmmo()` | effect data via `AmmoTypesAPI` |
| `CombinationLock.UnlockServer(...)` | `UnlockOnServer` (and `Unlock` is obsolete) |
| `CGame.VerifyWorldOwnership`, `CGame.GoBuyWorldDLC` | `ContentDLC` / `ContentDLCStorePrompt` |
| `MissionBenchmark`, `BenchmarkConfig`, `BenchmarkLocation` | – |
| `ActionActionBuildPartNoTool` | `ActionBuildPartHandsGeneric` family |
| `Settings`/`GameSettings`/`SettingsMenu` (2_GameLib) | – (was `#ifdef GAME_TEMPLATE`, never usable in DayZ; tested: unknown type) |
| `WeaponDebug` draw helpers, `ScriptConsole*Tab` constructors | rewritten |

### Moved up the hierarchy (calls keep working, overrides keep working)
- ~20 `CarScript` methods moved to `Transport` (sounds, crash sounds, `EEHitBy`, `OnContact`, `IsVitalFuelTank`,
  `IsVitalGlowPlug`, anim-source helpers, `CanPutIntoHands`, `EEDelete`) so boats and motorbikes share them.
- ~45 `Construction` methods moved to `ConstructionBase`. Construction is now a component any `EntityAI`
  can have (`EntityAI.GetConstructionBasic()`, `CanUseConstruction()`, ...); buildings use it for rebuilding.
- `Man.*TakeEntity*` inventory calls moved to `EntityAI`, so any entity can be the actor.
- `EEItemIntoHands`/`EEItemOutOfHands`/`EEFired` are declared on `EntityAI` now (`Man`/`Weapon_Base`
  override them). Existing overrides stay valid.
- `SlotsIcon` → `SlotsIconBase`, `ItemPreviewWidget`/`PlayerPreviewWidget` → `PreviewWidget` (model position/orientation).

### ERPCs values shifted
`RPC_SYMPTOM_PARAM_SYNC` was inserted near the top of `ERPCs`, plus several more values, so every vanilla ID
after `RPC_PLAYER_SYMPTOM_OFF` changes. Mods that store or send vanilla RPC IDs as **raw ints**
(or count from a vanilla value) break. Always use the enum names; keep mod RPC IDs in your own range.

### Changes in the stable update 25956772 → 25963285 (1.30.164200)
Found by diffing the shipped API index of both builds (declarations only, **not run on a server**). They hit mods
that touch base building, `ConstructionPart` data or custom actions.

| Before (25956772) | Now (25963285) | Notes |
|---|---|---|
| `ConstructionPart.GetSupportProvided(int category)` / `GetSupportRequirement(int category)` returning `int` | `bool GetSupportProvided(int category, out int providedStrength)` / `bool GetSupportRequirement(int category, out int requiredStrength)` | same change on `ConstructionPartStaticsSupportData` and on `ConstructionPartTypeData.GetPartTypeSupportProvided/Requirement`; callers and overrides both break |
| `ConstructionPart.TryHandleUtilityParts(EntityAI parent)` | `TryQueueUtilityPartsUpdate(ConstructionBase con)` | utility parts update through a queue: `QueueUpdateUtilityParts()`, `UpdateUtilityParts()` (returns `true` if changed) |
| `ConstructionPartTypeData.m_UtilityAutomaticBuild`, `GetPartTypeUtilityAutobuildPartsList()` | removed | `m_TriggersUtilityPartUpdate` / `TriggersUtilityPartsUpdate()` say whether a part state change triggers the utility update; `InitUtilityBuildData()` reads it from config |
| (none) | `InvertSupportBehavior()`, classes `ConstructionPartRebuildInvertedSupport` (+ `…TypeData`) | rebuilt parts that react inversely to support |
| (none) | `ConstructionBase.IgnoreHouseCollisions()` | map-authoring flag for rebuilt structures |
| `CarScript.IsMoving()` | now declared on `Transport` | calls keep working; an override in a `CarScript` subclass still compiles |
| `ActionBase` | adds `IsLockTargetOnUse()`, overridden by about 20 vanilla actions | only a problem if your action class declares a method of the same name with another signature |
| `MiscGameplayFunctions.FilterObstructedObjectsByGrouping(...)` | removed | |
| `NavmeshTest`, `NavmeshTest_A..F` | removed | test objects; only matters if a mod extends them |
| Workbench API in `workbenchApi.c` (`Workbench`, `WorldEditor`, `WorldEditorAPI`, ...) | split into `1_Core/WorkbenchAPI/` (`AnimEditor`, `GameViewer`, `BuildResourceContext`, `GeneratedResources`, ...) | only Workbench plugins; some old members are gone |

New without breaking anything: `FishingSplashEffect` / `FishingSplashEffecter` (fishing action particles),
`DateTimeUtcAsInt` (`GetYear/Month/Day/Hour/Minute/Second`).

## 4. Silent breakers

These compile on 1.30 but do something different.

1. **`OnCEUpdate()` is never called anymore (tested).** It is still declared (`[Obsolete]`, no body), so an
   override compiles with a warning, and then never runs. Over 2 minutes with 20 spawned items:
   1.30: `OnCEUpdate`=0 calls, `OnCEIterate`=446k. Port it:
   ```c
   	// before: override void OnCEUpdate() { super.OnCEUpdate(); MyMod_Decay(m_ElapsedSinceLastUpdate); }
   	override void OnCEIterate(float currentTime, float elapsedTime)
   	{
   		super.OnCEIterate(currentTime, elapsedTime);
   		MyMod_Decay(elapsedTime);
   	}
   ```
   Affects custom flags/totems, decaying items, explosives, contaminated areas, and anything with periodic CE logic.
2. **Custom car lights.** `CarScript.CreateFrontLight()`/`CreateRearLight()` are obsolete and **no longer called**.
   Lights come from `VehicleLightsComponent` (`m_LightsComponent`, created in `CarScript`'s constructor),
   and each car registers light profiles. A modded car that only overrides `CreateFrontLight` has no
   headlight beams on 1.30. Vanilla pattern (`Offroad_02`):
   ```c
   class MyCarLightProfileFront : VehicleLightProfileFront
   {
   	void MyCarLightProfileFront()
   	{
   		m_SegregatedBrightness = 5;   m_SegregatedRadius = 75;  m_SegregatedAngle = 90;
   		m_AggregatedBrightness = 10;  m_AggregatedRadius = 100; m_AggregatedAngle = 120;
   		m_SegregatedColorRGB = Vector(0.85, 0.85, 0.58);
   		m_AggregatedColorRGB = Vector(0.85, 0.85, 0.58);
   	}
   }
   class MyCarLightProfileRear : VehicleLightProfileBrakeAndReverse {}

   class MyCar : CarScript
   {
   	void MyCar()
   	{
   		m_LightsComponent.RegisterLight("Front", new VehicleLightData(new MyCarLightProfileFront()));
   		m_LightsComponent.RegisterLight("Rear", new VehicleLightData(new MyCarLightProfileRear()));
   		// RegisterSelection("BrakesOn"/"BrakesOff"/...) if your model's selections/materials differ
   	}
   	// the old override CreateFrontLight() (returning a CarLightBase) is no longer called: delete it
   }
   ```
   Brake, reverse and tail light helpers (`BrakesRearLight`, `TailLightsShineOn`, ...) are obsolete, too.
   Battery checks moved to `Transport.NeedElectricitySourceDevice()` (`IsVitalCarBattery`/`IsVitalTruckBattery` obsolete).
3. **AI noise.** Weather/sandstorm noise dampening moved into native `AIParams` config. Vanilla no longer
   multiplies noise by `GetNoiseReductionByWeather()`. Mods that scaled noise via `Weather` or
   `SensesAIEvaluate.GetNoiseReduction*` no longer change what AI hears.
4. **Liquid sources.** Drink/fill actions use the `CCTLiquid` target condition and `ActionObtainLiquidBase`.
   `CCTWaterSurface`, `ActionFillBottleBase` and `ActionWashHands*One` are obsolete or unregistered.
   `CCTLiquid` still honours `Object.IsWell()`; new is `Object.GetLiquidSourceObjectType()` (`ELiquidSourceObjectType`).
   Custom drink/fill actions built on `ActionFillBottleBase` or `CCTWaterSurface` should move to the new classes on 1.30.
5. **Explosion effects** per surface moved from `ExplosivesBase.AddExplosionEffectForSurface` to `AmmoTypes`.
   Old registrations are ignored.
6. **Surrender**: `EmoteManager` surrender handling → `PlayerBase.SetSurrenderState(bool)` / `IsSurrendered()`
   (now on `Man`). `SurrenderDummyItem` is unused.
7. **Persistence**: `GAME_STORAGE_VERSION` 142 → 144. A storage written by 1.30 should be treated as not
   loadable by older servers. Back up `storage_1` before upgrading; there is no way back. Mods using `OnStoreLoad(ctx, version)` gates keep working.
8. **Third person**: `World.Is3rdPersonDisabled()` is obsolete. 1.30 has three modes,
   `World.GetThirdPersonViewMode()` → `ThirdPersonMode.DISABLED / ENABLED / VEHICLES_ONLY`, and
   `Is3rdPersonDisabled()` cannot express "vehicles only".

## 5. Obsolete in 1.30

Compile with `SCRIPT (W): '...' is obsolete` **(tested)**, so plan to switch. 

| Obsolete | Replacement |
|---|---|
| `*TakeEntityToCargo`, `*TakeEntityAsAttachment(Ex)`, `*TakeEntityToCargoEx` (Predictive/Local/Server/Juncture, `GameInventory.TakeEntity*`) | `*TakeEntityToTargetCargo(target, item)`, `*TakeEntityToTargetAttachment(Ex)(target, item[, slot])`, `*TakeEntityToTargetCargoEx(cargo, item, row, col)` |
| `EntityAI.OnCEUpdate()` | `OnCEIterate(float currentTime, float elapsedTime)` |
| `EntityAI.CanDisplayAttachmentSlot(string)` | `CanDisplayAttachmentSlot(int slot_id)` |
| `World.Is3rdPersonDisabled()` | `World.GetThirdPersonViewMode()` |
| `World.UpdatePathgraphDoorByAnimationSourceName` | `World.UpdatePathgraphEntityState(obj)` |
| `CGame.SurfaceUnderObject*`, `Surface.GetStepsParticleID/GetWheelParticleID`, `DayZPlayerImplement.GetSurfaceType` | `CGame.GetSurfaceInfoUnderObject(obj)`, `GetSurfaceInfoUnderObjectByBone`, `GetSurfaceInfoOn(x, z, out h)` → `SurfaceInfo` |
| `CarScript` light helpers, `CreateFrontLight/RearLight`, `*FrontLight` classes | `VehicleLightsComponent`, `VehicleLightBase`, `VehicleLightProfile*` |
| `CarScript.IsVitalCarBattery/IsVitalTruckBattery`, `CheckVitalItem`, `CarPartsHealthCheck` | `Transport.NeedElectricitySourceDevice`, `CheckVitalItemCallback`, `PartsHealthCheck` |
| `CarScript.IsScriptedLightsOn()` | `LightIsOn()` |
| `ActionCarHorn*` | `ActionVehicleHornShort/Long` |
| `ActionFillBottleBase`, `CCTWaterSurface` | `ActionObtainLiquidBase`, `CCTLiquid` |
| `ConstructionBase.BuildPartServer/DismantlePartServer/IsColliding` | `BuildPartServerEx/DismantlePartServerEx/IsCollidingEx` |
| `ConstructionPart.m_Name/m_PartName/m_Id/m_IsBase/m_IsGate/...` | `ConstructionPartTypeData` |
| `ConstructionActionData.SetSlotId/GetSlotId` | overridden `ActionData` |
| `ActionBuildPart.SetBuildingAnimation` | `SetBuildingAnimationEx` |
| `MiscGameplayFunctions.GenerateAINoiseAtPosition`, old `BuildCondition`/`ComplexBuildCollideCheckClient` | `GenerateAINoiseAtPositionEx`, new overloads |
| `Weather.GetNoiseReductionByWeather*`, `SensesAIEvaluate.GetNoiseReduction*` | native `AIParams` |
| `CombinationLock.Unlock/IsLockedOnGate/SetDigitRotationAnimationPhase/AnimateDigits`, lock sound methods | `UnlockOnServer`, `IsLocked`, `...Outside/...Inside` variants, `ItemSoundHandler` |
| `ExplosivesBase` surface effect registry | `AmmoTypes` |
| `ItemBase.GetDryingIncrement/GetSoakingIncrement(string)` | overloads taking `EEnvironmentDryingCategories` / `EEnvironmentSoakingCategories` |
| `ItemBase.GetHeatIsolationInit`, `ClearStartItemSoundServer`, `UndergroundStash.PlaceOnGround`, `ActionTargetsCursor.Set*XboxIcon` | none |
| `VicinityItemManager.GetFixedHeadHeightAdjustment` | `MiscGameplayFunctions.GetPlayerHeadHeight` |

## 6. New APIs in 1.30

- **Version / platform**: `CGame.IsHeadless()`, `CGame.IsHeadlessOrDedicatedServer()` (headless roboclients
  exist now: `ROBOCLIENT` define, `-roboclient`). Prefer `IsHeadlessOrDedicatedServer()` over `IsDedicatedServer()`
  for "no rendering" checks on 1.30.
- **Objects**: `CGame.CreateObject(..., bool objSpawner = false)`, `CreateStaticObjectUsingP3D(..., bool objSpawner = false)`.
  Building doors: `Building.CanDoorBeOpened(DoorManipulationParams)`, `CanDoorBeClosed(int, Object)`, `GetDoorInfo(idx)`.
  `Object.GetLiquidSourceObjectType()`, `Object.IsExplosive()`.
- **Construction everywhere**: `EntityAI.GetConstructionBasic()`, `CanUseConstruction*()`,
  `EntityAIType.GetConstructionDataHolderBasic()`; rebuilding of map structures (`Rebuilding`, `RebuildingSpawner`).
- **Code locks**: `CodeLock`, `CodeLockComponent`, `DigitalCodeLockUI`, RPCs `RPC_CODE_LOCK_*`; `ItemBase.IsExternalLockType()`;
  `cfggameplay.json` `ExternalLockData` (protection counts/times).
- **Vehicles**: motorbikes (`Motorbike : Transport`, `MotorbikeScript`, `MotorBikeHud`), `Transport.CanGetIn()`,
  `CrewCanEject/CrewShouldEject`, `GetElectricitySourceDevice()`, `FillScript/GetFluidCapacityScript/GetFluidFractionScript(ETransportFluid, ...)`,
  `Car.WheelGetPositionLS(idx)`, `VehicleVFXComponent`, `VehicleHornComponent`.
  `cfggameplay.json`: `canDetach/DamageAttachedCarWheels`, `canDetach/DamageAttachedBikeWheels`.
- **Weather**: `Weather.GetSandstorm()` → `Sandstorm`; `Object.IsInfluencedBySandstorm()`, `OnClientSandstormEnter/Leave()`;
  `World.GetSunOrMoonDirection()`; `cfggameplay.json` `SandstormData.sandstormFrequency`.
- **Bunkers**: `CGame.GetBunkerBroadcastManager()`, `cfggameplay.json` `bunkerBroadcastEnabled`, `disableBaseDecay`.
- **Player**: `PlayerBase.GetThermalBiasHandler()`, `GetUndergroundPresence()`, new diseases (`HeatStroke`, `Silicosis`).
- **Script core**: `vector.Cross(v)`, `vector.SanitizeMinsMaxs(inout min, inout max)`, `array.Slice(from, to)` (inclusive),
  `typename.EnumFlagsToString` / `EnumTools.EnumFlagsToString`, `RGBToHSV`/`HSVToRGB`, `COLOR_CYAN/MAGENTA`,
  `ProjectWorldToViewport`/`ProjectViewportToWorld`, `DoOnce`, `SimpleCircularBuffer` additions.
  These are pure script: you can copy them into a mod that must also run on older versions.
- **Maps**: Nasdara (`nasdara` define, `Nasdara` world class, `DynamicMusicPlayerRegistryNasdara`). `ModInfo.GetDLCID()` is new.

## 7. Experimental builds

1.30 is stable now; the Experimental branch carries the next build. It is optional for testing ahead of a release.

- Experimental runs a **diag build**: `DEVELOPER`, `DIAG_DEVELOPER`, `BUILD_EXPERIMENTAL`, `ENABLE_LOGGING` are defined.
  - Code under `#ifdef DIAG_DEVELOPER` compiles and runs there, and disappears on stable.
  - `Error()` and `ErrorEx(..., ErrorExSeverity.WARNING)` show up as `SCRIPT (E): Virtual Machine Exception`
    with a stack trace (tested on 1.30.164014). That is noisy but not fatal. Use `Print`/your logger for expected warnings.
  - More vanilla diag code runs, so script logs are noisier (e.g. `Leaked 'BunkerBroadcastManager'` at shutdown).
- Separate Steam apps: Experimental Server **1042420** ("DayZ Server Exp"), Experimental client **1024020**
  ("DayZ Exp"). Workshop items for the experimental client live under `workshop/content/1024020`.
  `scripts/find-dayzserver.sh -e` finds them; see `testing/local-server.md`.
- Vanilla baseline on 1.30.164014: Game module 440 files. Compare a mod boot against a vanilla boot of the same build.
- A mod that fails to compile can make the 1.30 server **segfault** right after `Can't compile "World" script module!`.

## 8. Review checklist

Run this on every mod written for 1.29 or older. Each grep is a quick first pass, not a proof. Boot the mod on a
1.30 server (`testing/local-server.md`) and read `script_*.log` for `(E)` and `(W)`.

```
[ ] server start: -profiles=<dir> inside the server executable's folder (symlink ok); CF 1.5.9+ (no CF-Test/COT-Test)
[ ] grep -rn 'FindFile' → CF.FindFileEx (or the YOURMOD_FindFilePath fallback without CF); open results via placeholder paths
[ ] grep -rn '\\\\' in path strings → forward slashes everywhere (configs read from JSON too)
[ ] grep -rn 'files\[\]' config.cpp → CfgMods script module paths with forward slashes (backslashes: 1.30 loads no scripts, silently)
[ ] grep -rn '\$storage:' → never before the first OnUpdate/CallLater tick after OnMissionStart; not on a first boot (no storage_1); FindFile on it breaks on 1.30
[ ] grep -rn 'GetMissionFolderPath' → returns "" on servers; derive from GetMissionPath()
[ ] grep -rn 'ProcessVariables\|OnCEUpdate\|m_ElapsedSinceLastUpdate\|m_LastUpdatedTime' → ProcessVariables(float elapsedTime) / OnCEIterate
[ ] grep -rn 'CreateFrontLight\|CreateRearLight\|ToggleHeadlights\|m_HeadlightsOn\|IsVital\(Car\|Truck\)Battery' → VehicleLightsComponent / LightToggle
[ ] grep -rn 'SetParent\|class .*: *Construction\b\|modded class Construction' → new ConstructionBase API
[ ] grep -rn 'CombinationLock' → new signatures, inside/outside sides
[ ] grep -rn 'TakeEntityToCargo\|TakeEntityAsAttachment' → *TakeEntityToTarget* 
[ ] grep -rn 'ERPCs\.' and raw RPC ints → enum names only
[ ] grep -rn 'GetExplosionParticleID\|AddExplosionEffectForSurface\|ShootsExplosiveAmmo' → AmmoTypesAPI.GetExplosiveEffectData
[ ] grep -rn 'Is3rdPersonDisabled\|SurfaceUnderObject\|CCTWaterSurface\|ActionFillBottleBase\|ActionCarHorn' → see §5
[ ] grep -rn 'DIAG_DEVELOPER\|BUILD_EXPERIMENTAL' → must not be used as "is 1.30"
[ ] grep -rn 'GetSupportProvided\|GetSupportRequirement\|TryHandleUtilityParts\|m_UtilityAutomaticBuild' → 25963285 signatures (§3, stable update table)
[ ] Overrides of anything in §3 table → signature
[ ] Boot on a 1.30 server: no (E), review (W) obsolete warnings
[ ] Back up storage_1 before the first 1.30 boot (older servers cannot read it back)
```
