# Packaging, Signing and Publishing a DayZ Mod (armake2 + workshop uploader)

Turn a source tree into a Workshop-ready folder without DayZ Tools or Windows:
**armake2** builds and signs the PBOs, **workshop** (steam-workshop-uploader) uploads the folder.
**armake2 must be bzed's fork** (see below): upstream armake2 produces mods that fail on servers. The uploader is the upstream https://github.com/nozwock/steam-workshop-uploader, which supports DayZ.
`scripts/dayz-mod-pack.sh` wires the two together; this file explains what it does and what the other
armake2 commands are for.

Verified on Linux with the bzed armake2 fork (v0.3.0), DayZ Server 1.29.163709 (not re-run on 1.30): a PBO built, signed and
verified with this flow loads with `-mod=@Mod` and `verifySignatures = 2`, and its scripts run.
The maintainer has since used the armake2 fork and the uploader end to end for real uploads ("working well").
**Not verified here:** the v3-vs-v2 signature check on a real client.

## The bzed armake2 fork is required

Tested: upstream `KoffeinFlummi/armake2` **ignores `*.c` files when it creates signatures**, so the `.bisign` of a script
mod does not cover its scripts and the result is not a correct DayZ signature. It also fails on DayZ configs. You **need**
**https://github.com/bzed/armake2** (upstream remote kept, rebased on upstream master). The uploader needs no fork
(see "Uploading with `workshop`"). Fork changes in armake2:
preprocessor grammar fixes (`#include` directives, nested macro arguments), `$PREFIX$` accepted when
building PBOs, `paa2img` / `img2paa`, opt-in `build --proton-binarize` (models via BI binarize.exe under Proton on Linux), current Rust and dependency versions, a Dockerfile/`build.sh`,
and an end-to-end DayZ test harness (`testharness/run.sh [--both]`: build, sign, boot a server, check logs).

**Look for an installed armake2 first**, then check what it can do; only build the fork if it is missing or too old:

```sh
command -v armake2 && armake2 -h 2>&1 | grep -- --proton-binarize   # a hit = bzed fork; no hit = upstream, do not use
armake2 --version
```

The fork is identified by `--proton-binarize` (upstream signs `*.c` wrongly, fails on DayZ configs). Signatures from the
fork work fine (maintainer-tested). `build --proton-binarize` also converts `.p3d`/`.rtm` natively on Linux.

```sh
git clone https://github.com/bzed/armake2 && cd armake2 && cargo build --release   # needs libssl-dev
install -m755 target/release/armake2 ~/.bin/       # any directory in PATH
# or in one step:  cargo install --git https://github.com/bzed/armake2 --root ~/.local   (binary in ~/.local/bin)
```

Build from the fork's current `master` on GitHub. Checked 2026-11-03: `master` at `7dcb3cf`, installed with `cargo install --git`,
is detected as the fork and keeps texture alpha with `--proton-binarize` (see below). A build from an older checkout may not:
`armake2 --version` prints `v0.3.0` either way, so when in doubt, reinstall from GitHub.

`dayz-mod-pack.sh` does this check itself: it uses the `armake2` from `PATH` (or `$ARMAKE2`), refuses to run when it is
upstream, and for `--binarize-models` picks `--proton-binarize` when available.

## Quick start

```sh
S=${CLAUDE_SKILL_DIR}/scripts/dayz-mod-pack.sh
$S init MyMod        # folders, .gitignore, .workshopignore
# put sources in src/<Addon>/ (config.cpp, $PREFIX$, scripts/, data/ ...), one folder per PBO
$S keygen            # secrets/MyMod.biprivatekey (never committed) + keys/MyMod.bikey (public)
$S build             # build/@MyMod/{addons,keys} (+ mod.cpp if you wrote one) - this folder is what you upload
$S build --binarize-models   # same, and convert .p3d/.rtm to ODOL via binarize.exe under Proton (Linux)
$S check             # no key in git/history/upload folder, every signature verifies
$S publish-hint      # prints the exact `workshop create|update` commands (does not run them)
```

`ModName` becomes the key name and defaults the PBO prefix; keep it to letters, digits and `_`.
Pass `-C <dir>` to work on another project directory.

### Layout

```
MyMod/                     git repository
├── .dayzmod               MOD_NAME=MyMod
├── .gitignore             secrets/  *.biprivatekey  build/
├── .workshopignore        extra ignore list handed to the uploader
├── mod.cpp                optional launcher metadata; copied into the content folder if present
├── src/MyMod/             -> addons/MyMod.pbo   (config.cpp, $PREFIX$, scripts/, data/)
├── src/MyMod_Data/        -> addons/MyMod_Data.pbo (optional further addons)
├── static/                copied verbatim into the content folder (logo.paa, ...)
├── keys/MyMod.bikey       PUBLIC key; commit it, hand it to server owners
├── secrets/               PRIVATE key. Git-ignored. Back it up somewhere else, too.
├── workshop.toml          written by the uploader on `create`; commit it, build re-copies it
└── build/@MyMod/          generated Workshop content (git-ignored)
    ├── mod.cpp            (only if the project has one)
    ├── addons/MyMod.pbo + MyMod.pbo.MyMod.bisign
    ├── keys/MyMod.bikey
    └── workshop.toml
```

### Why the private key is handled this way

- The `.biprivatekey` lives in `secrets/`, outside every folder that is packed or uploaded. `build`
  aborts if one shows up under the content folder, `keygen` refuses to run when `secrets/` is not
  git-ignored, and the PBO excludes and `.workshopignore` skip `*.biprivatekey` as a last line of defence.
- `keygen` never overwrites. Replacing a key invalidates all existing signatures and makes every server
  owner install a new `.bikey`; if a key ever reached git history or the Workshop, treat it as leaked and
  rotate it (new key name, e.g. `MyMod_V2`, so old and new can coexist in `keys/` during the switch).
- `check` fails when a `.biprivatekey` is tracked or present anywhere in history. Rewriting history does
  not un-leak a key that was pushed; rotate it.
- Do not commit `build/`: it is reproducible, and a signature is only valid for the exact PBO bytes.

## Binarization: what armake2 can and cannot do

`build` (the script's default) is "binarize" as far as Linux allows:

| Input | `armake2 build` | `armake2 pack` |
|---|---|---|
| `config.cpp` (any `*.cpp`) | preprocessed, rapified to `config.bin` | copied as text |
| `*.rvmat` | rapified | copied |
| `*.p3d`, `*.rtm` | **copied as-is** on Linux (warning `non-windows-binarization`) unless `--proton-binarize` is given; BI's `binarize.exe` runs on Windows, or under Proton with that flag (see the texture caveat below) | copied |
| `.c` scripts, `.paa`, `.ogg`, `.wss`, ... | copied | copied |

Consequences: rapified `config.bin` is the default because it is smaller, faster to load and what the
official tools produce; scripts always stay text. Models must be binarized (MLOD to ODOL) in DayZ Tools
or the PBO ships MLOD models, which load but are bigger and slower. Textures must already be `.paa`;
convert PNG/TGA with `armake2 img2paa -t dxt5 -c in.png out_co.paa` (`-t dxt1` for opaque maps; keep
power-of-two sizes). Use `--no-bin` (`armake2 pack`) to ship `config.cpp` untouched, e.g. when
debugging a rapify problem. A `$NOBIN$` or `$NOBIN-NOTEST$` file in an addon folder disables
binarization for that addon only.

### DayZ Tools under Proton: link the game data into the tools prefix

DayZ Tools (Steam app 830640) and the game (221100, or 1024020 for Experimental) are separate Steam apps, so each runs in its
own Wine prefix under `steamapps/compatdata/<appid>/pfx`. The tools themselves run fine under Proton; AddonBuilder packs
without problems (maintainer-tested). What fails is any tool step that needs **game data** (vanilla `dz\...` textures, configs and models,
for example binarizing a model that references vanilla textures, or tools that look up the game install), because
the tools prefix does not know where the game is. Link the game into that prefix before blaming the tool.

State observed on the maintainer's machine (2026-11-03):

| | game prefix `compatdata/221100` | tools prefix `compatdata/830640` |
|---|---|---|
| `HKLM\Software\Wow6432Node\Bohemia Interactive\DayZ` | `"main"="S:\steamapps\common\DayZ"` | key exists, **no `main` value** |
| drives (`pfx/dosdevices`) | `c:`, `z:` → `/` | `c:`, `z:` → `/`, `s:` → Steam root, no `p:` |

What the link involves:
- the `main` value in the tools prefix pointing at the game install (through `s:` or `z:`)
- a `p:` with the game data the tool resolves, i.e. an extracted `dz\...` tree next to your own addon prefix (see the binarize recipe below)

Re-tested 2026-11-03 (Proton Hotfix, DayZ Tools build 26405911) in fresh throwaway prefixes. Besides the two items above, a
prefix that Steam never launched lacks what Steam does on a tool's first launch: the `Registry` entries of
`DayZ Tools/installscript.vdf` (without them TexView stops at "Missing registry entry
HKEY_LOCAL_MACHINE/Software\BIStudio\TextureConvert") and the VC++ runtime from `Steamworks Shared/_CommonRedist/vcredist`
(Object Builder does not start without `mfc140.dll`). Also measured: the 32-bit tools need `PROTON_USE_WOW64=1` when the host
has no i386 FreeType (dialogs without text otherwise); the first .NET tool started in a fresh prefix never finishes (later
starts work); a prefix's wineserver is bound to one display (a tool started on another display dies with `X Error … BadWindow`);
AddonBuilder exits 0 on a failed build (the result is `[ResultCode]` in `DayZ Tools/Bin/Logs/AddonBuilder.rpt`). With those
handled, ImageToPAA, CfgConvert, the DS tools, AddonBuilder (also full builds), binarize, TexView, Object Builder, Workbench
and DayZDiag (client and `-server`) ran. The DayZ Modding Knowledge Pack ships a runner that does all of this in private
prefixes: `skills/_shared/scripts/dayz-proton.sh` (`init <P-dir>`, then `tool`/`gui`/`binarize`/`headless`), with the measured
matrix in `skills/_shared/linux-proton.md`. Still prefer armake2 for building and signing.

Never edit or write into the Steam install directories themselves. A throwaway prefix
(`STEAM_COMPAT_DATA_PATH` in `/tmp` or `/var/tmp`, as in the recipe below) keeps experiments out of the real tools prefix.

### `binarize.exe` under Proton: works if Wine's `Z:` drive is tiny

`dayz-mod-pack.sh build --binarize-models` passes `--proton-binarize` to armake2, which does the recipe below itself: it creates a
temporary sandbox and Wine prefix (first run takes a while), converts every `.p3d`/`.rtm` from a staging copy (your sources stay
MLOD), builds and signs, and deletes the sandbox. It finds DayZ Tools and Proton under the Steam root (override with
`STEAM_ROOT`, `DAYZ_TOOLS`, `PROTON`) and fails with the binarize log if a model does not convert.

**Texture alpha: fixed in the fork since `0a0ce3b` (upstream #21).** binarize.exe resolves face texture paths
(`mymod\data\glass_ca.paa`) **relative to its current directory**, and BI's tools run it from `P:\`. Fork builds before
`0a0ce3b` copied only the `.p3d` into the sandbox and ran binarize from the `Binarize` folder, so no texture was found and no
error was printed: the ODOL's section flags lost `0x802020` (IsAlpha|IsTransparent|IsAlphaFog) and the face colour fell
back to the not-found default (measured 2026-10-31, binarize 1.30.164200.56). `0a0ce3b` runs binarize from a `P:` root with
the addon mapped. Verified 2026-11-03 (binarize 1.30.164289.70, Proton Hotfix, a cube textured with a DXT5 `_ca.paa`): a fork
build from HEAD `7dcb3cf` gives output **byte-identical** to binarize run by hand from a `P:` root, and to AddonBuilder's binarized
model; an older build still differed in 20 bytes. `armake2 --version` prints `v0.3.0` for both, so the version does not tell
them apart: if in doubt, rebuild the fork from source, or binarize one textured model both ways and `cmp` the results.
Not checked in game.

Upstream armake2 only calls BI's `binarize.exe` (DayZ Tools, Steam app 830640) on Windows, so on Linux `.p3d`/`.rtm`
stay MLOD; the bzed fork adds `build --proton-binarize` (Linux, opt-in). Running the exe yourself under Proton works, with one trap. Wine maps `Z:` to `/`, and Binarize
walks directory trees from that root: it burned CPU for minutes without output (a strace showed it listing
unrelated directories such as `~/.cargo`, plus a CIFS mount), whether the input file existed or not, with or
without a fake `P:` drive. A `Z:` that contains only what Binarize needs fixes it: 3 s, exit code 0.
Tested with Proton Hotfix (Steam's default compat tool here) and DayZ Tools from Steam:

```sh
W=$(mktemp -d)                                   # sandbox that becomes Wine's Z:
cp -r "$STEAM/steamapps/common/DayZ Tools/Bin/Binarize" "$W/Binarize"
mkdir -p "$W/out" "$W/prefix" "$W/P/mymod"       # P/<prefix path> = your addon (prefix mymod here)
cp -r src/MyMod/. "$W/P/mymod/"                  # model + its textures, at the paths the model references
export STEAM_COMPAT_CLIENT_INSTALL_PATH="$STEAM" STEAM_COMPAT_DATA_PATH="$W/prefix" SteamAppId=830640
"$STEAM/steamapps/common/Proton Hotfix/proton" run cmd.exe /c exit   # first run creates the prefix
ln -sfn "$W"   "$W/prefix/pfx/dosdevices/z:"     # confine Z: to the sandbox
ln -sfn "$W/P" "$W/prefix/pfx/dosdevices/p:"     # P: = project root
cd "$W/P"                                        # current directory = P:\, so textures resolve
"$STEAM/steamapps/common/Proton Hotfix/proton" run 'Z:\Binarize\binarize.exe' \
    -norecurse -always -silent -maxProcesses=0 'P:\mymod' 'Z:\out' model.p3d   # result: $W/out/model.p3d
```

Use backslash paths with a drive letter. A model without textures binarizes from any directory: a hand-made MLOD triangle
came out as `ODOL` version 7. With textures, **the current directory must be the `P:` root** (see the known bug
above). An strace showed binarize stat'ing `<cwd>\mymod\data\glass_ca.paa`. Textures from other addons (vanilla `dz\…`)
are only found if they also exist under `P:` (extracted game data). Drop `-silent` and redirect through
`cmd /c "… > Z:\out\log.txt 2>&1"` to get the log ("Convert model …", "No model config used").
**Not verified:** loading such an ODOL on a server. Do not kill leftover Wine processes with `pkill -f binarize...` from a shell whose own command line
contains that text; it kills your shell. On Windows, armake2 finds the exe itself through the registry key
`HKCU\Software\Bohemia Interactive\binarize` (`path` = folder with `binarize_x64.exe`) and `build` binarizes
`.p3d`/`.rtm` in one go (not tested here).

### Checking armake2 against BI's own tools (Proton)

When armake2 output is in doubt, run the same input through DayZ Tools in a sandbox set up as above (copy the tool
folder, e.g. `Bin/CfgConvert` or `Bin/DsUtils`, into `$W`; `cd` into it; `Z:` confined to `$W`). Tested 2026-10-31, Proton Hotfix:

```sh
proton run ./CfgConvert.exe -bin -dst 'Z:\out\x.bin' 'Z:\in\x.cpp'   # then: armake2 derapify $W/out/x.bin
proton run cmd /c 'DSSignFile.exe Z:\k\Name.biprivatekey Z:\p\x.pbo > Z:\out\log.txt 2>&1'
proton run cmd /c 'DSCheckSignatures.exe -deep Z:\p Z:\k > Z:\out\log.txt 2>&1'
```

- The DS tools print nothing on Proton's console. Redirect through `cmd /c … > file` to see their output.
- Compare CfgConvert and armake2 output **after `derapify`**, not byte for byte: CfgConvert writes a 4-byte offset
  after every class body and armake2 does not. The decoded configs are identical, and the game loads both.
- A PBO edited by hand needs its SHA-1 trailer recomputed (`\0` + `sha1(everything before it)`), or DSSignFile
  fails with "Stored and calculated hash don't match".

### armake2 config/PBO bugs found against CfgConvert (2026-10-31): fixed in the fork's `master`

Found with fork `782396e` against CfgConvert on 2026-10-31. Each has a fix commit in the fork, and each was re-tested
on 2026-11-03 with `master` (`7dcb3cf`) installed from GitHub (`cargo install --git https://github.com/bzed/armake2`):

| Was | Now (re-tested) | Fix |
|---|---|---|
| unquoted string value (`simulation = inventoryItem;`) swallowed the rest of the file | ends at `;`, `}` or newline, like CfgConvert | `bcb2244` |
| already-rapified `.rvmat` failed `build` | passed through | `ae05ebd` |
| `#include "x.hpp"  // comment` failed | accepted | `45379fd` |
| `#include "inc.hpp"` did not find `Inc.hpp` on Linux | case-insensitive fallback | `d24b0c1` |
| macro with the wrong argument count stayed unexpanded, silently | warning, expands to `""` like CfgConvert | `563b944`, `ec58d08` |
| `__EVAL`/`__EXEC` not evaluated; a warning on line 1 crashed | `__EVAL(1+2*3)` → `7` | `f6465e9`, `b928152` |
| non-UTF-8 (cp1252) entry names: `inspect`/`unpack` crashed | warning, extracted as windows-1252 | `698cfcf`, `173319f` |

An older local build still has these bugs, and `--version` prints `v0.3.0` for every build: reinstall from GitHub.

**Still open (found 2026-11-03):** `armake2 pack` of a source folder that holds a file whose *Linux* name is not valid
UTF-8 (e.g. `caf\xe9.txt`) exits without an error and writes a PBO that `inspect` and `unpack` refuse with
`Failed to read PBO: failed to fill whole buffer`. Rename such files to UTF-8 before packing. (A PBO extracted by armake2
itself writes UTF-8 names, so this mostly hits trees extracted by other tools.)

`-e product=dayz` (set by the script) goes into the PBO header next to `prefix=`.

## Signatures

- `armake2 keygen <path/Name>` writes `<Name>.biprivatekey` and `<Name>.bikey` (1024-bit RSA; the key
  name is stored inside both files and in the signature file name).
- `armake2 sign <key.biprivatekey> <x.pbo>` writes `x.pbo.<KeyName>.bisign` next to the PBO. The
  `.bisign` must sit beside its PBO with exactly that name, in the same `addons/` folder.
- Default is the **v3** signature. `--v2` writes the older v2 form; use it only if a client or server
  rejects v3 (`build --v2` in the script). v3 was not tested against a real client here.
- `armake2 verify <Name.bikey> <x.pbo> [x.pbo.Name.bisign]` checks a signature (exit code 0 = valid).
- Tested 2026-10-31 against DayZ Tools (DsUtils) under Proton: for a PBO with `config.bin`, a `.c` script and an
  rvmat, the fork's v3 `.bisign` is **byte-identical** to `DSSignFile.exe`'s, and `DSCheckSignatures.exe -deep`
  reports it OK.
- Sign **after** the final build; any change to the PBO (even a rebuild with a different timestamp or
  header) invalidates the old `.bisign`. The script always rebuilds and re-signs together.
- Server owners copy `keys/<Name>.bikey` into the server's `keys/` folder; with `verifySignatures = 2`
  the server rejects clients whose PBOs lack a valid signature for an installed key.

## Everything else armake2 can do

```
armake2 rapify     [-i inc]... [src [dst]]     config.cpp -> config.bin (preprocesses first)
armake2 derapify   [-d indent] [src [dst]]     config.bin -> readable config text
armake2 preprocess [-i inc]... [src [dst]]     expand #include/#define, print the result
armake2 build      [-i inc] [-x glob] [-e k=v] [-k key] [-s sig] <dir> [pbo]   rapify + pack
armake2 pack       [-x glob] [-e k=v] [-k key] [-s sig] <dir> [pbo]            pack, no rapify
armake2 inspect    <pbo>                       list header extensions and files with sizes
armake2 unpack     [-x glob] <pbo> <dir>       extract; header lands in $PBOPREFIX$
armake2 cat        <pbo> <file> [dst]          print one file from a PBO (use \ in the inner path)
armake2 keygen / sign / verify                 see above
armake2 img2paa    [-t dxt1|dxt5] [-c] <img> <paa>     image -> PAA
armake2 paa2img    <paa> <img>                 PAA -> png/other image
armake2 binarize                               Windows only (BI binarize.exe); not usable on Linux
```

Common flags: `-v` verbose, `-f` overwrite targets, `-w <name>` silence a warning,
`-i <dir>` include search path (default `.`), `-x <glob>` exclude from the PBO, `-e key=value` extra
PBO header, `-k key` sign right after building (v3), `-s sig` explicit signature path. Without a
source/target, `rapify`, `preprocess` and `derapify` read stdin and write stdout (`cat` writes stdout), which makes them
usable in pipes. Debug recipes:

- "Why does my config not build": `armake2 preprocess src/MyMod/config.cpp | less` shows what the parser sees.
- "What did the official PBO set": `armake2 inspect Vanilla.pbo` and `armake2 cat Vanilla.pbo config.bin | armake2 derapify`.
- "Is my prefix right": `armake2 inspect x.pbo` must show `prefix=<what config.cpp's script paths start with>`.
  With `-e`/`$PREFIX$` unset, the folder name becomes the prefix.
- `$PREFIX$` content: one line `MyMod`, or `key=value` lines (`prefix=MyMod`). Use `MyMod\Sub` for nested prefixes.

## What goes into the upload folder: `mod.cpp`, `meta.cpp`, and the app id

Checked against the 438 items in a local Steam workshop directory (`workshop/content/221100`) and the strings in
the official DayZ Publisher (`DayZ Tools/Bin/Publisher`):

| File | In real Workshop mods | Contains the app id? | Who creates it |
|---|---|---|---|
| `addons/*.pbo` (+ `.bisign`) | yes; the Publisher refuses an upload without an `addons` folder in the root, or with `.pbo` files outside it (`addons` and `Addons` both occur) | no | armake2 (`build`, `sign`) |
| `keys/*.bikey` | in most mods (some server-side-only items have none) | no | `keygen` |
| `mod.cpp` | 135 of 438 (optional, not needed) | **no, in none of them** | you, if you want it; `init` does not write one |
| `meta.cpp` | 438 of 438 | **no** | the official Publisher; `dayz-mod-pack.sh build` mirrors it (id 0 before the first upload, like the Windows tools; the real id after) |

So the assumption "the app id has to be in `mod.cpp`" does not hold. The id travels outside the mod:
the Publisher reads it from its own `steam_appid.txt` (`221100`), and the `workshop` uploader takes `--app-id 221100`
and stores it in `workshop.toml` (which is never uploaded). Do not add an app id to `mod.cpp`.

**`mod.cpp`** fields seen in real mods, in order of frequency: `name`, `overview`, `tooltip`, `action` (URL),
`author`, `picture`, `logo`, `logoSmall`, `logoOver`, `version`, `authorID` (Steam64 id); rarely `type`,
`description`, `hidePicture`. `picture`/`logo*` are paths inside a PBO (CF uses
`"JM/CF/GUI/textures/cf_icon.edds"`), so a logo has to ship in one of your addons. Keep `name`, `author`,
`version` filled in; everything else can stay empty. 303 of the 438 installed items ship no `mod.cpp` at all, so it is optional. The maintainer reports a mod works fine without it (**tested** by the maintainer, no build number recorded); what the launcher shows for
such an item was not checked. A locally loaded `-mod=` folder works without `meta.cpp` and `mod.cpp`.

**`meta.cpp`** (the Publisher writes it into every upload):

```
protocol = 1;
publishedid = 1559212036;      // the Workshop item id
name = "CF";                   // the item title
timestamp = 5250757174595880000;
```

`timestamp` is .NET `DateTime.ToBinary()` of the UTC upload time: `(unix_seconds + 62135596800) * 10^7 + 2^62`
(decoded CF's value gives 2026-02-19, the build date of its PBO). The item id only exists after the first upload. The official
Windows tools upload `meta.cpp` with `publishedid = 0` on a first publish (`mod-structure.md`: 0 = unpublished).
That **does not work for DayZ clients** (server mods are fine with it), but it is what those tools do. So
`dayz-mod-pack.sh build` always writes a `meta.cpp` (id 0 until `workshop.toml` holds an `item_id`, the real id
afterwards) so the folder is complete for local tests.

With the **upstream uploader** this is all you need: on every DayZ (app 221100) `create` and `update` it creates
or updates `meta.cpp` in the content folder (`publishedid` from the new item / `workshop.toml`, fresh `timestamp`,
other fields kept) before it uploads. Tested by the maintainer. Flow: `workshop create ... --visibility private`, copy
`workshop.toml` to the project root and commit it, check the item, make it public in Steam; later releases are
`build` + `update`. An uploader that does not touch it would upload the `publishedid = 0` meta.cpp as is, which breaks client
mods (server mods are fine). Whether a client needs anything else
from `meta.cpp` was not tested.

## Workshop tags

Tags come in two groups. (Type/content split as given by the maintainer from the Workshop upload dialog; the
counts below are from Steam's public API, `ISteamRemoteStorage/GetPublishedFileDetails`, for the 438 items in a
local workshop directory, 434 still available.)

**Type tag: exactly one of**

| Tag | Use |
|---|---|
| `Mod` | every normal mod (client and server) |
| `Server` | servermods only (loaded with `-servermod=`) |

**Content tags: any number, combinable with either type tag**

`Animation`, `Character`, `Economy`, `Environment`, `Equipment`, `Mechanics`, `Props`, `Sound`, `Terrain`, `Vehicle`,
`Weapon`. Pick the ones that describe what the mod adds; none is required. (Seen on the 434 items: `Mechanics` 118,
`Equipment` 103, `Environment` 84, `Props` 75, `Character` 69, `Terrain` 46, `Sound` 38, `Economy` 37, `Vehicle` 32,
`Animation` 32, `Weapon` 32.)

`Tag Review` is set by moderation; never set it yourself. There is no `servermod` or `Scenario` tag to use (the
Publisher refuses `Mod` together with `Scenario`).

The sample is older than this rule: all 434 items carry `Mod`, and 14 carry `Mod` together with `Server`. Do not copy
that; a servermod gets `Server` instead of `Mod`. Not tested: whether Steam or the Publisher rejects both type tags
at once, or none.

In the script the tags live in `.dayzmod` as `WORKSHOP_TAGS="Mod Weapon"` (`init <Name> --servermod` writes
`"Server"`). `check` fails unless exactly one of `Mod`/`Server` is present and warns about unknown tags;
`publish-hint` turns them into repeated `-t` options. `workshop create -t Mod -t Weapon ...` stores them in
`workshop.toml`, `update` reuses them from there (Steam drops tags that are not sent along).

## Uploading with `workshop`

Source: **https://github.com/nozwock/steam-workshop-uploader** (Rust, bundles Steamworks; supports DayZ and
maintains `meta.cpp` on upload; the former bzed fork is no longer needed). Look for `workshop` in `PATH` first. The Steam client must
be running and logged in as an account that owns DayZ; the DayZ client app id is **221100**.

```sh
# first upload: creates the item and writes workshop.toml into the content folder (the app id goes here, not into mod.cpp)
workshop create --app-id 221100 --content build/@MyMod --title "My Mod" -t Mod \
    --ignore-file .workshopignore --glob '!*.biprivatekey' --visibility private -m "first upload"
cp build/@MyMod/workshop.toml workshop.toml && git add workshop.toml     # item id is not secret

# later releases: build + update (the uploader refreshes meta.cpp itself); always `workshop --no-prompt update`, so it never asks questions or needs a tty
workshop --no-prompt update --content build/@MyMod --ignore-file .workshopignore --glob '!*.biprivatekey' -m "changelog"
```

- `workshop.toml` (`app_id`, `item_id`, `tags`) tells `update` which item to overwrite; it is never uploaded.
- The uploader makes a filtered staging copy first, honouring `.ignore`/`.gitignore`, `--ignore-file` and
  `--glob`. Globs are case-sensitive; a leading `!` excludes. `--no-prompt` (a global option, so it goes before the subcommand) disables interactive questions.
- Start with `--visibility private` (or `unlisted`), subscribe to the item with another account or check the
  Workshop page, then flip it public in Steam.
- Uploading publishes content to Steam and may be cached by clients; it is the user's decision. Run
  `check` and look at the content folder first; do not run `create`/`update` unprompted.
- `meta.cpp`: see above; the uploader keeps it current on every upload.

## Pitfalls

- **Prefix vs script paths**: `CfgMods` `files[] = {"MyMod/scripts/3_Game"}` only resolves if the PBO
  prefix is `MyMod`. A wrong or missing prefix loads the PBO but compiles none of its scripts.
- **One key per mod family**: sign every PBO of a mod with the same key so one `.bikey` covers all.
- **Server mods vs client mods**: PBOs for `-servermod=` need no key on clients; `-mod=` mods do.
- **Case and separators**: PBO inner paths use `\`; `armake2 cat` needs `'scripts\5_Mission\x.c'`.
- **Large asset mods**: `build` loads files in memory; very large PBOs need RAM to match.
- **Testing**: boot the result with `testing/local-server.md` (`-mod=@MyMod`, copy `keys/MyMod.bikey`
  into the tree's `keys/`) and compare script module counts with vanilla before uploading.
