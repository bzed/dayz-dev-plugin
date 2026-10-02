# DayZ 1.30 Compatibility Guide (and targeting 1.29 + 1.30 at once)

> **Status (Oct 2026):** 1.30 is on **Experimental** (1.30.164014.27). PC Stable release is planned for
> **October 15, 2026**. Until then, mods must keep working on **1.29 stable** *and* be fixed for 1.30.
> **Source of truth:** script diff 1.29.163709 → 1.30.164014 (local `dayz-sources` git, tags `1.29` / `1.30`)
> plus test mods booted on a 1.29.163709 stable and a 1.30.164014.27 experimental dedicated server
> (Linux, Oct 2, 2026). Statements marked **(tested)** were observed on both servers; the rest come
> from reading the 1.30 source. Re-check after each experimental update, since BI may fix DZEXP-134.
> Remote references (diff.yadz.app, DayZ-Script-Diff) may still show 1.29: use the local source.

Diff 1.29 → 1.30, scripts only: 837 files, +53k/−12k lines. New content (Nasdara map, sandstorms,
motorbikes, code locks, bunker radio broadcasts, rebuilding of map structures) drives most of it.
The sections below cover what affects mods.

## Contents
1. [Targeting both versions: `DAYZ_1_29` / `DAYZ_1_30`](#1-targeting-both-versions)
2. [File paths: `$profile:`, `$mission:`, forward slashes, `FindFile`](#2-file-paths-and-findfile)
3. [Compile breakers (overrides and calls)](#3-compile-breakers)
4. [Silent breakers (compile fine, behave differently)](#4-silent-breakers)
5. [Obsolete in 1.30 (warnings)](#5-obsolete-in-130)
6. [New APIs](#6-new-apis)
7. [Experimental server gotchas](#7-experimental-server-gotchas)
8. [Review checklist](#8-review-checklist)

---

## 1. Targeting both versions

**The engine defines the version (tested).** The script-module `defines:` line in `script_*.log` shows:

| Server | Defines (excerpt) |
|---|---|
| 1.29.163709 stable | `DAYZ_1_29, SERVER, RELEASE, NO_GUI, ...` |
| 1.30.164014 experimental | `DAYZ_1_30, SERVER, DEVELOPER, DIAG_DEVELOPER, BUILD_EXPERIMENTAL, ...` |

Only the current version's define exists: 1.30 does **not** define `DAYZ_1_29`, and 1.29 did not define
`DAYZ_1_28`. So write the *old* code under `#ifdef DAYZ_1_29` and the new code in `#else`. Then the new
code automatically becomes the default for 1.30, 1.31, ..., and the 1.29 branch is easy to delete later:

```c
modded class ItemBase
{
#ifdef DAYZ_1_29
	override void ProcessVariables()
	{
		super.ProcessVariables();
		MyMod_Tick();
	}
#else
	override void ProcessVariables(float elapsedTime)
	{
		super.ProcessVariables(elapsedTime);
		MyMod_Tick();
	}
#endif
}
```
`#ifdef DAYZ_1_30` would silently drop the code again on 1.31, so don't use it for "new" code.

Rules:
- **Prefer APIs that exist in both versions** over `#ifdef`. Already available in 1.29:
  `*TakeEntityToTarget*` inventory calls, `Transport.LightOn/LightOff/LightToggle/LightIsOn`,
  `ConstructionBase/Construction.IsCollidingEx`, `HitZoneSelectionRaycast`. **(tested: compile on both)**
- One PBO, one source tree works: `#ifdef` is resolved when the server compiles the scripts, so the same
  build loads on 1.29 and 1.30 **(tested)**. No separate experimental build is needed.
- Runtime version string: `string v; g_Game.GetVersion(v);` gives `"1.29.163709"` / `"1.30.164014.27"`
  **(tested)**. Use it for logging. It cannot select code that would not compile, so use the define for that.
- Your own defines work too: `defines[] = {"MYMOD"};` in `CfgMods` → `#ifdef MYMOD` **(tested)**.
- **Do not use `BUILD_EXPERIMENTAL`/`DIAG_DEVELOPER` to mean "1.30".** They are defined on every
  experimental build and will be gone on 1.30 stable.

## 2. File paths and FindFile

**What changed (tested, server side):** on 1.30, `FindFile()` ignores the `$profile:`, `$mission:`,
`$storage:` and `$saves:` placeholders. It returns **no error**, but silently lists the server's working
directory instead (`FindFile("$profile:*")` returned `DayZServer`, `addons`, `keys`, ...).
Backslash paths find nothing. BI tracks it as **DZEXP-134**; it may or may not be fixed by release.

Results of the test matrix (each cell: 1.29 / 1.30):

| Operation | `$profile:` `$mission:` `$saves:` (either slash) | relative `profiles/x/` fwd slash | relative, backslash | absolute fwd slash | `$storage:` |
|---|---|---|---|---|---|
| `MakeDirectory`, `OpenFile` R/W, `FileExist`, `CopyFile`, `DeleteFile`, `JsonFileLoader` | ✅ / ✅ | ❌ / ✅* | ❌ / ✅* | – | ❌ / ❌ |
| `FindFile` | ✅ / ❌ **wrong dir** | ✅ / ✅ | ✅ / ❌ | ❌ / ✅ | ❌ / ❌ |

\* writable on the experimental server; that may be a `DEVELOPER`-build relaxation. Don't rely on it.

Consequences:
- **Keep using `$profile:` / `$mission:` / `$saves:` for every file function except `FindFile`.** It works
  on both versions. `$storage:` does not work on a server even on 1.29; build that path yourself.
- **Use forward slashes in every path you build.** They work everywhere on both versions; backslashes
  break `FindFile` on 1.30. This includes paths assembled from parts (`dir + "/" + name`, not `"\\"`).
- **Wrap every `FindFile` pattern** with the bundled helper `compatibility/YOURMOD_FindFilePath.c`
  (rename `YOURMOD`, drop into `3_Game`). On 1.29 it leaves `$profile:`/`$mission:` alone (only flips
  slashes); on 1.30 it resolves them; `$storage:` is resolved on both **(tested on both servers)**:
  ```c
  string fileName;
  FileAttr attr;
  FindFileHandle h = FindFile(YOURMOD_FindFilePath("$profile:YOURMOD/*.json"), fileName, attr, FindFileFlags.ALL);
  if (fileName != "")   // first match comes back in fileName; "" = nothing found
  {
      do
      {
          // fileName is a bare name: open it with the placeholder path, not the resolved one
          MyMod_Load("$profile:YOURMOD/" + fileName);
      }
      while (FindNextFile(h, fileName, attr));
  }
  if (h)
      CloseFindFile(h);
  ```
- Resolution sources: `$profile:` ← `-profiles=` CLI param (required; a server started without it can't be
  resolved), `$mission:` ← folder of `g_Game.GetMissionPath()`, `$storage:` ← `-storage=<dir>` if given,
  else `<mission folder>`, plus `/storage_<instanceId>` (`serverDZ.cfg` `instanceId`, default 1).
- **`g_Game.GetMissionFolderPath()` returns `""`** on both 1.29 and 1.30 servers (tested): vanilla's
  `SetMissionPath` only splits on `\`, but the engine passes `mpmissions/<mission>/mission.c`.
  Derive the folder from `GetMissionPath()` instead, as the helper does.
- The community gist `YOURMOD_FindFile_DZEXP134_Helper.c` (lava76) has bugs: a stray `)` (does not compile),
  `"storage_%1"` instead of `%2`, and its `serverDZ.cfg` `template=` parser keeps the trailing
  `"; // comment` of the stock config, so it fails with VM exceptions. The bundled helper replaces it.
- Mods that only *read a known file name* (`JsonFileLoader.LoadFile("$profile:MyMod/config.json")`) are
  unaffected. Mods that *enumerate* a directory (load all `*.json`, list saved loadouts, rotate logs)
  break silently: they find nothing, or the server root's files.
- Client side was not tested; assume the same `FindFile` behavior.

## 3. Compile breakers

Each of these stops the module from compiling on 1.30. On the experimental server, a script compile failure
was followed by a **segfault** of the server (tested). A crash at boot is often a compile error, so read
`script_*.log` first.

### Override signature changes (tested where marked)
| 1.29 override | 1.30 | Notes |
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
| Removed in 1.30 | Use instead | In 1.29? |
|---|---|---|
| `CarScript.ToggleHeadlights()` **(tested)** | `LightToggle()` (on `Transport`) | yes: switch now |
| `CarScript.GenerateCarHornAINoise`, `CarHorn*ActionInput` | `VehicleHornComponent` (`Transport.GetVehicleHornComponent()`), `VehicleHornShort/LongActionInput`, `ActionVehicleHornShort/Long` | no |
| `CarScript.m_ForceUpdateLights` | – (`ForceUpdateLightsStart/End` obsolete, no replacement) | |
| `EntityAI/ItemBase.m_ElapsedSinceLastUpdate`, `EntityAI.m_LastUpdatedTime` | `elapsedTime` parameter of `OnCEIterate`/`ProcessVariables` | no |
| `ItemBase.m_ItemActionOverrides` | `OverrideActionAnimation`/`SetActionAnimOverrides` now live on `EntityAI` | |
| `AmmoTypesAPI.GetExplosionParticleID(ammo, surface)` | `AmmoTypesAPI.GetExplosiveEffectData(ammo, surface)` → `.m_ParticleID`, `.m_SoundSetName` | no |
| `Ammo_40mm_Explosive.ShootsExplosiveAmmo()` | effect data via `AmmoTypesAPI` | |
| `CombinationLock.UnlockServer(...)` | `UnlockOnServer` (and `Unlock` is obsolete) | no |
| `CGame.VerifyWorldOwnership`, `CGame.GoBuyWorldDLC` | `ContentDLC` / `ContentDLCStorePrompt` | |
| `MissionBenchmark`, `BenchmarkConfig`, `BenchmarkLocation` | – | |
| `ActionActionBuildPartNoTool` | `ActionBuildPartHandsGeneric` family | |
| `Settings`/`GameSettings`/`SettingsMenu` (2_GameLib) | – (was `#ifdef GAME_TEMPLATE`, never usable in DayZ; tested: unknown type on both) | |
| `WeaponDebug` draw helpers, `ScriptConsole*Tab` constructors | rewritten | debug/admin tools |

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

## 4. Silent breakers

These compile on 1.30 but do something different.

1. **`OnCEUpdate()` is never called anymore (tested).** It is still declared (`[Obsolete]`, no body), so an
   override compiles with a warning, and then never runs. Over 2 minutes with 20 spawned items:
   1.29: `OnCEUpdate`=553k calls; 1.30: `OnCEUpdate`=0, `OnCEIterate`=446k. Port it:
   ```c
   #ifdef DAYZ_1_29
   	override void OnCEUpdate()
   	{
   		super.OnCEUpdate();
   		MyMod_Decay(m_ElapsedSinceLastUpdate);
   	}
   #else
   	override void OnCEIterate(float currentTime, float elapsedTime)
   	{
   		super.OnCEIterate(currentTime, elapsedTime);
   		MyMod_Decay(elapsedTime);
   	}
   #endif
   ```
   Affects custom flags/totems, decaying items, explosives, contaminated areas, and anything with periodic CE logic.
2. **Custom car lights.** `CarScript.CreateFrontLight()`/`CreateRearLight()` are obsolete and **no longer called**.
   Lights come from `VehicleLightsComponent` (`m_LightsComponent`, created in `CarScript`'s constructor),
   and each car registers light profiles. A modded car that only overrides `CreateFrontLight` has no
   headlight beams on 1.30. Vanilla pattern (`Offroad_02`):
   ```c
   #ifndef DAYZ_1_29
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
   #endif

   class MyCar : CarScript
   {
   	void MyCar()
   	{
   	#ifndef DAYZ_1_29
   		m_LightsComponent.RegisterLight("Front", new VehicleLightData(new MyCarLightProfileFront()));
   		m_LightsComponent.RegisterLight("Rear", new VehicleLightData(new MyCarLightProfileRear()));
   		// RegisterSelection("BrakesOn"/"BrakesOff"/...) if your model's selections/materials differ
   	#endif
   	}
   #ifdef DAYZ_1_29
   	// MyCarFrontLight : CarLightBase is the mod's existing 1.29 light class
   	override CarLightBase CreateFrontLight() { return CarLightBase.Cast(ScriptedLightBase.CreateLight(MyCarFrontLight)); }
   #endif
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
   loadable by 1.29. Never point a 1.29 and a 1.30 server at the same `storage_1`, and back up before
   upgrading. Mods using `OnStoreLoad(ctx, version)` gates keep working.
8. **Third person**: `World.Is3rdPersonDisabled()` is obsolete. 1.30 has three modes,
   `World.GetThirdPersonViewMode()` → `ThirdPersonMode.DISABLED / ENABLED / VEHICLES_ONLY`, and
   `Is3rdPersonDisabled()` cannot express "vehicles only".

## 5. Obsolete in 1.30

Compile with `SCRIPT (W): '...' is obsolete` **(tested)**, so plan to switch. "1.29" = the replacement already exists in 1.29.

| Obsolete | Replacement | 1.29 |
|---|---|---|
| `*TakeEntityToCargo`, `*TakeEntityAsAttachment(Ex)`, `*TakeEntityToCargoEx` (Predictive/Local/Server/Juncture, `GameInventory.TakeEntity*`) | `*TakeEntityToTargetCargo(target, item)`, `*TakeEntityToTargetAttachment(Ex)(target, item[, slot])`, `*TakeEntityToTargetCargoEx(cargo, item, row, col)` | ✅ |
| `EntityAI.OnCEUpdate()` | `OnCEIterate(float currentTime, float elapsedTime)` | ❌ |
| `EntityAI.CanDisplayAttachmentSlot(string)` | `CanDisplayAttachmentSlot(int slot_id)` | ✅ |
| `World.Is3rdPersonDisabled()` | `World.GetThirdPersonViewMode()` | ❌ |
| `World.UpdatePathgraphDoorByAnimationSourceName` | `World.UpdatePathgraphEntityState(obj)` | ❌ |
| `CGame.SurfaceUnderObject*`, `Surface.GetStepsParticleID/GetWheelParticleID`, `DayZPlayerImplement.GetSurfaceType` | `CGame.GetSurfaceInfoUnderObject(obj)`, `GetSurfaceInfoUnderObjectByBone`, `GetSurfaceInfoOn(x, z, out h)` → `SurfaceInfo` | ❌ |
| `CarScript` light helpers, `CreateFrontLight/RearLight`, `*FrontLight` classes | `VehicleLightsComponent`, `VehicleLightBase`, `VehicleLightProfile*` | ❌ |
| `CarScript.IsVitalCarBattery/IsVitalTruckBattery`, `CheckVitalItem`, `CarPartsHealthCheck` | `Transport.NeedElectricitySourceDevice`, `CheckVitalItemCallback`, `PartsHealthCheck` | ❌ |
| `CarScript.IsScriptedLightsOn()` | `LightIsOn()` | ✅ |
| `ActionCarHorn*` | `ActionVehicleHornShort/Long` | ❌ |
| `ActionFillBottleBase`, `CCTWaterSurface` | `ActionObtainLiquidBase`, `CCTLiquid` | ❌ |
| `ConstructionBase.BuildPartServer/DismantlePartServer/IsColliding` | `BuildPartServerEx/DismantlePartServerEx/IsCollidingEx` | `IsCollidingEx` only |
| `ConstructionPart.m_Name/m_PartName/m_Id/m_IsBase/m_IsGate/...` | `ConstructionPartTypeData` | ❌ |
| `ConstructionActionData.SetSlotId/GetSlotId` | overridden `ActionData` | ❌ |
| `ActionBuildPart.SetBuildingAnimation` | `SetBuildingAnimationEx` | ❌ |
| `MiscGameplayFunctions.GenerateAINoiseAtPosition`, old `BuildCondition`/`ComplexBuildCollideCheckClient` | `GenerateAINoiseAtPositionEx`, new overloads | ❌ |
| `Weather.GetNoiseReductionByWeather*`, `SensesAIEvaluate.GetNoiseReduction*` | native `AIParams` | – |
| `CombinationLock.Unlock/IsLockedOnGate/SetDigitRotationAnimationPhase/AnimateDigits`, lock sound methods | `UnlockOnServer`, `IsLocked`, `...Outside/...Inside` variants, `ItemSoundHandler` | ❌ |
| `ExplosivesBase` surface effect registry | `AmmoTypes` | ❌ |
| `ItemBase.GetDryingIncrement/GetSoakingIncrement(string)` | overloads taking `EEnvironmentDryingCategories` / `EEnvironmentSoakingCategories` | ❌ |
| `ItemBase.GetHeatIsolationInit`, `ClearStartItemSoundServer`, `UndergroundStash.PlaceOnGround`, `ActionTargetsCursor.Set*XboxIcon` | none | – |
| `VicinityItemManager.GetFixedHeadHeightAdjustment` | `MiscGameplayFunctions.GetPlayerHeadHeight` | ❌ |

## 6. New APIs (1.30 only: guard with `#ifndef DAYZ_1_29`)

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
  These are pure script: copy them into your mod if you need them on 1.29.
- **Maps**: Nasdara (`nasdara` define, `Nasdara` world class, `DynamicMusicPlayerRegistryNasdara`). `ModInfo.GetDLCID()` is new.

## 7. Experimental server gotchas

- Experimental runs a **diag build**: `DEVELOPER`, `DIAG_DEVELOPER`, `BUILD_EXPERIMENTAL`, `ENABLE_LOGGING` are defined.
  - Code under `#ifdef DIAG_DEVELOPER` compiles and runs there, and disappears on 1.30 stable.
  - `Error()` and `ErrorEx(..., ErrorExSeverity.WARNING)` show up as `SCRIPT (E): Virtual Machine Exception`
    with a stack trace (tested). That is noisy but not fatal. Use `Print`/your logger for expected warnings.
  - More vanilla diag code runs, so script logs are noisier (e.g. `Leaked 'BunkerBroadcastManager'` at shutdown).
- Separate Steam apps: Experimental Server **1042420** ("DayZ Server Exp"), Experimental client **1024020**
  ("DayZ Exp"). Workshop items for the experimental client live under `workshop/content/1024020`.
  `scripts/find-dayzserver.sh -e` finds them; see `testing/local-server.md`.
- Vanilla baseline: 1.29 Game module 416 files / 1.30 experimental 440 files.
- A mod that fails to compile can make the 1.30 server **segfault** right after `Can't compile "World" script module!`.

## 8. Review checklist

Run this on every mod before Oct 15. Each grep is a quick first pass, not a proof. Boot the mod on both
servers (`testing/local-server.md`) and read `script_*.log` for `(E)` and `(W)`.

```
[ ] grep -rn 'FindFile' → wrap every pattern with YOURMOD_FindFilePath(); open results via placeholder paths
[ ] grep -rn '\\\\' in path strings → forward slashes everywhere (configs read from JSON too)
[ ] grep -rn '\$storage:' → build the storage path yourself (never worked on servers)
[ ] grep -rn 'GetMissionFolderPath' → returns "" on servers; derive from GetMissionPath()
[ ] grep -rn 'ProcessVariables\|OnCEUpdate\|m_ElapsedSinceLastUpdate\|m_LastUpdatedTime' → #ifdef DAYZ_1_29 / OnCEIterate
[ ] grep -rn 'CreateFrontLight\|CreateRearLight\|ToggleHeadlights\|m_HeadlightsOn\|IsVital\(Car\|Truck\)Battery' → VehicleLightsComponent / LightToggle
[ ] grep -rn 'SetParent\|class .*: *Construction\b\|modded class Construction' → new ConstructionBase API
[ ] grep -rn 'CombinationLock' → new signatures, inside/outside sides
[ ] grep -rn 'TakeEntityToCargo\|TakeEntityAsAttachment' → *TakeEntityToTarget* (works on 1.29 too: switch now)
[ ] grep -rn 'ERPCs\.' and raw RPC ints → enum names only
[ ] grep -rn 'GetExplosionParticleID\|AddExplosionEffectForSurface\|ShootsExplosiveAmmo' → AmmoTypesAPI.GetExplosiveEffectData
[ ] grep -rn 'Is3rdPersonDisabled\|SurfaceUnderObject\|CCTWaterSurface\|ActionFillBottleBase\|ActionCarHorn' → see §5
[ ] grep -rn 'DIAG_DEVELOPER\|BUILD_EXPERIMENTAL' → must not be used as "is 1.30"
[ ] Overrides of anything in §3 table → signature
[ ] Boot on 1.29 stable AND 1.30 experimental: same mod build, no (E), review (W) obsolete warnings
[ ] Never share storage_1 between a 1.29 and a 1.30 server
```
