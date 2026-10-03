# Packaging, Signing and Publishing a DayZ Mod (armake2 + workshop uploader)

Turn a source tree into a Workshop-ready folder without DayZ Tools or Windows:
**armake2** builds and signs the PBOs, **workshop** (steam-workshop-uploader) uploads the folder.
`scripts/dayz-mod-pack.sh` wires the two together; this file explains what it does and what the other
armake2 commands are for.

Verified on Linux with the bzed armake2 fork (v0.3.0), DayZ Server 1.29.163709: a PBO built, signed and
verified with this flow loads with `-mod=@Mod` and `verifySignatures = 2`, and its scripts run.
**Not verified:** a real client connecting with the signature check, and the Steam upload itself.

## Use the fork, not upstream armake2

Upstream `KoffeinFlummi/armake2` fails on DayZ configs and lacks things DayZ mods need. Use
**https://github.com/bzed/armake2** (upstream remote kept, rebased on upstream master). Fork changes:
preprocessor grammar fixes (`#include` directives, nested macro arguments), `$PREFIX$` accepted when
building PBOs, `paa2img` / `img2paa`, opt-in `build --proton-binarize` (models via BI binarize.exe under Proton on Linux), current Rust and dependency versions, a Dockerfile/`build.sh`,
and an end-to-end DayZ test harness (`testharness/run.sh [--both]`: build, sign, boot a server, check logs).

**Look for an installed armake2 first**, then check what it can do; only build the fork if it is missing or too old:

```sh
command -v armake2 && armake2 --help | grep -c paa2img          # 1 = bzed fork (DayZ fixes), 0 = upstream
armake2 --help | grep -q proton-binarize && echo "can binarize models (Proton)"
armake2 --version
```

| `armake2 --help` shows | Meaning | What to do |
|---|---|---|
| no `paa2img` | upstream armake2; fails on DayZ configs | install the fork |
| `paa2img`, no `proton-binarize` | fork without model binarization | works for configs/PBOs/signing; `--binarize-models` falls back to the script's own Proton staging |
| `proton-binarize` | current fork (`master` of https://github.com/bzed/armake2) | everything; `build --proton-binarize` converts `.p3d`/`.rtm` natively on Linux |

```sh
git clone https://github.com/bzed/armake2 && cd armake2 && cargo build --release   # needs libssl-dev
install -m755 target/release/armake2 ~/.bin/       # any directory in PATH
```

`dayz-mod-pack.sh` does this check itself: it uses the `armake2` from `PATH` (or `$ARMAKE2`), warns when it is
upstream, and for `--binarize-models` picks `--proton-binarize` when available.

## Quick start

```sh
S=${CLAUDE_SKILL_DIR}/scripts/dayz-mod-pack.sh
$S init MyMod        # folders, .gitignore, .workshopignore, mod.cpp stub
# put sources in src/<Addon>/ (config.cpp, $PREFIX$, scripts/, data/ ...), one folder per PBO
$S keygen            # secrets/MyMod.biprivatekey (never committed) + keys/MyMod.bikey (public)
$S build             # build/@MyMod/{addons,keys,mod.cpp} - this folder is what you upload
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
├── mod.cpp                copied into the content folder
├── src/MyMod/             -> addons/MyMod.pbo   (config.cpp, $PREFIX$, scripts/, data/)
├── src/MyMod_Data/        -> addons/MyMod_Data.pbo (optional further addons)
├── static/                copied verbatim into the content folder (logo.paa, ...)
├── keys/MyMod.bikey       PUBLIC key; commit it, hand it to server owners
├── secrets/               PRIVATE key. Git-ignored. Back it up somewhere else, too.
├── workshop.toml          written by the uploader on `create`; commit it, build re-copies it
└── build/@MyMod/          generated Workshop content (git-ignored)
    ├── mod.cpp
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
| `*.p3d`, `*.rtm` | **copied as-is** on Linux (warning `non-windows-binarization`); BI's `binarize.exe` is used only on Windows | copied |
| `.c` scripts, `.paa`, `.ogg`, `.wss`, ... | copied | copied |

Consequences: rapified `config.bin` is the default because it is smaller, faster to load and what the
official tools produce; scripts always stay text. Models must be binarized (MLOD to ODOL) in DayZ Tools
or the PBO ships MLOD models, which load but are bigger and slower. Textures must already be `.paa`;
convert PNG/TGA with `armake2 img2paa -t dxt5 -c in.png out_co.paa` (`-t dxt1` for opaque maps; keep
power-of-two sizes). Use `--no-bin` (`armake2 pack`) to ship `config.cpp` untouched, e.g. when
debugging a rapify problem. A `$NOBIN$` or `$NOBIN-NOTEST$` file in an addon folder disables
binarization for that addon only.

### `binarize.exe` under Proton: works if Wine's `Z:` drive is tiny

`dayz-mod-pack.sh build --binarize-models` automates the recipe below (with a current fork it just passes
`--proton-binarize` to armake2, which does the same internally; the script's own staging is the fallback for older builds): it creates a temporary sandbox and Wine
prefix (first run takes a while), converts every `.p3d`/`.rtm` in a staging copy of each addon (your sources stay
MLOD), builds and signs from the staging copy, and deletes the sandbox. It finds DayZ Tools and Proton under the Steam
root (override with `STEAM_ROOT`, `DAYZ_TOOLS`, `PROTON`) and fails with the binarize log if a model does not convert.
Tested with the one-triangle model above only.

Upstream armake2 only calls BI's `binarize.exe` (DayZ Tools, Steam app 830640) on Windows, so on Linux `.p3d`/`.rtm`
stay MLOD; the bzed fork adds `build --proton-binarize` (Linux, opt-in). Running the exe yourself under Proton works, with one trap. Wine maps `Z:` to `/`, and Binarize
walks directory trees from that root: it burned CPU for minutes without output (a strace showed it listing
unrelated directories such as `~/.cargo`, plus a CIFS mount), whether the input file existed or not, with or
without a fake `P:` drive. A `Z:` that contains only what Binarize needs fixes it: 3 s, exit code 0.
Tested with Proton Hotfix (Steam's default compat tool here) and DayZ Tools from Steam:

```sh
W=$(mktemp -d)                                   # sandbox that becomes Wine's Z:
cp -r "$STEAM/steamapps/common/DayZ Tools/Bin/Binarize" "$W/Binarize"
mkdir -p "$W/in" "$W/out" "$W/prefix"; cp model.p3d "$W/in/"
ln -sfn "$W" "$W/prefix/pfx/dosdevices/z:"       # after the first proton run created the prefix (see below)
export STEAM_COMPAT_CLIENT_INSTALL_PATH="$STEAM" STEAM_COMPAT_DATA_PATH="$W/prefix" SteamAppId=830640
cd "$W/Binarize"
"$STEAM/steamapps/common/Proton Hotfix/proton" run ./binarize.exe \
    -norecurse -always -silent -maxProcesses=0 'Z:\in' 'Z:\out' model.p3d     # result: $W/out/model.p3d
```

The prefix is created by the first `proton run`, so run any trivial command once (or run Binarize once, kill it
after a few seconds) and then replace `pfx/dosdevices/z:` with the symlink to the sandbox. Use backslash
paths with a drive letter; no `P:` drive is needed. Verified: a hand-made MLOD triangle (`MLOD`) came out as
`ODOL` version 7. **Not verified:** a real model with textures/materials (those resolve against `P:`, so a
real project needs the `P:` drive pointing at the project root inside the sandbox), and loading the ODOL in a
server. Do not kill leftover Wine processes with `pkill -f binarize...` from a shell whose own command line
contains that text; it kills your shell. On Windows, armake2 finds the exe itself through the registry key
`HKCU\Software\Bohemia Interactive\binarize` (`path` = folder with `binarize_x64.exe`) and `build` binarizes
`.p3d`/`.rtm` in one go (not tested here).

`-e product=dayz` (set by the script) goes into the PBO header next to `prefix=`.

## Signatures

- `armake2 keygen <path/Name>` writes `<Name>.biprivatekey` and `<Name>.bikey` (1024-bit RSA; the key
  name is stored inside both files and in the signature file name).
- `armake2 sign <key.biprivatekey> <x.pbo>` writes `x.pbo.<KeyName>.bisign` next to the PBO. The
  `.bisign` must sit beside its PBO with exactly that name, in the same `addons/` folder.
- Default is the **v3** signature. `--v2` writes the older v2 form; use it only if a client or server
  rejects v3 (`build --v2` in the script). v3 was not tested against a real client here.
- `armake2 verify <Name.bikey> <x.pbo> [x.pbo.Name.bisign]` checks a signature (exit code 0 = valid).
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
| `mod.cpp` | 135 of 438 (optional; the launcher shows its fields) | **no, in none of them** | you; `init` writes a stub |
| `meta.cpp` | 438 of 438 | **no** | the official Publisher; `dayz-mod-pack.sh build` mirrors it once the item exists |

So the assumption "the app id has to be in `mod.cpp`" does not hold. The id travels outside the mod:
the Publisher reads it from its own `steam_appid.txt` (`221100`), and the `workshop` uploader takes `--app-id 221100`
and stores it in `workshop.toml` (which is never uploaded). Do not add an app id to `mod.cpp`.

**`mod.cpp`** fields seen in real mods, in order of frequency: `name`, `overview`, `tooltip`, `action` (URL),
`author`, `picture`, `logo`, `logoSmall`, `logoOver`, `version`, `authorID` (Steam64 id); rarely `type`,
`description`, `hidePicture`. `picture`/`logo*` are paths inside a PBO (CF uses
`"JM/CF/GUI/textures/cf_icon.edds"`), so a logo has to ship in one of your addons. Keep `name`, `author`,
`version` filled in; everything else can stay empty. 303 of the 438 installed items ship no `mod.cpp` at all, so it is optional; what the launcher shows for
such an item was not tested. A locally loaded `-mod=` folder works without `meta.cpp` and `mod.cpp`.

**`meta.cpp`** (the Publisher writes it into every upload):

```
protocol = 1;
publishedid = 1559212036;      // the Workshop item id
name = "CF";                   // the item title
timestamp = 5250757174595880000;
```

`timestamp` is .NET `DateTime.ToBinary()` of the UTC upload time: `(unix_seconds + 62135596800) * 10^7 + 2^62`
(decoded CF's value gives 2026-02-19, the build date of its PBO). The `workshop` uploader does not write the file,
and the item id only exists after the first upload, so `dayz-mod-pack.sh build` writes it whenever `workshop.toml`
holds an `item_id`:

1. `build`, then `workshop create ...`: the first upload has no `meta.cpp`.
2. Copy `build/@MyMod/workshop.toml` to the project root and commit it.
3. `build` again: `meta.cpp` is now written. Then `workshop update ...`. Every later release is just `build` + `update`.

Whether a client or the launcher needs `meta.cpp` (for example to map a folder to its Workshop id) was not
tested; writing it keeps the upload identical to what the official tool produces.

## Uploading with `workshop`

Source: https://github.com/nozwock/steam-workshop-uploader (Rust, bundles Steamworks). The Steam client must
be running and logged in as an account that owns DayZ; the DayZ client app id is **221100**.

```sh
# first upload: creates the item and writes workshop.toml into the content folder (the app id goes here, not into mod.cpp)
workshop create --app-id 221100 --content build/@MyMod --title "My Mod" \
    --ignore-file .workshopignore --glob '!*.biprivatekey' --visibility private -m "first upload"
cp build/@MyMod/workshop.toml workshop.toml && git add workshop.toml     # item id is not secret

# then rebuild (writes meta.cpp from workshop.toml) and publish that; later releases: build + update
workshop update --content build/@MyMod --ignore-file .workshopignore --glob '!*.biprivatekey' -m "changelog"
```

- `workshop.toml` (`app_id`, `item_id`, `tags`) tells `update` which item to overwrite; it is never uploaded.
- The uploader makes a filtered staging copy first, honouring `.ignore`/`.gitignore`, `--ignore-file` and
  `--glob`. Globs are case-sensitive; a leading `!` excludes. `--no-prompt` disables interactive questions.
- Start with `--visibility private` (or `unlisted`), subscribe to the item with another account or check the
  Workshop page, then flip it public in Steam.
- Uploading publishes content to Steam and may be cached by clients; it is the user's decision. Run
  `check` and look at the content folder first; do not run `create`/`update` unprompted.
- `meta.cpp`: see above; the script writes it from `workshop.toml` after the first upload.

## Pitfalls

- **Prefix vs script paths**: `CfgMods` `files[] = {"MyMod/scripts/3_Game"}` only resolves if the PBO
  prefix is `MyMod`. A wrong or missing prefix loads the PBO but compiles none of its scripts.
- **One key per mod family**: sign every PBO of a mod with the same key so one `.bikey` covers all.
- **Server mods vs client mods**: PBOs for `-servermod=` need no key on clients; `-mod=` mods do.
- **Case and separators**: PBO inner paths use `\`; `armake2 cat` needs `'scripts\5_Mission\x.c'`.
- **Large asset mods**: `build` loads files in memory; very large PBOs need RAM to match.
- **Testing**: boot the result with `testing/local-server.md` (`-mod=@MyMod`, copy `keys/MyMod.bikey`
  into the tree's `keys/`) and compare script module counts with vanilla before uploading.
