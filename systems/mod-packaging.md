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
building PBOs, `paa2img` / `img2paa`, current Rust and dependency versions, a Dockerfile/`build.sh`,
and an end-to-end DayZ test harness (`testharness/run.sh [--both]`: build, sign, boot a server, check logs).

```sh
git clone https://github.com/bzed/armake2 && cd armake2 && cargo build --release   # needs libssl-dev
install -m755 target/release/armake2 ~/.bin/       # any directory in PATH
armake2 --help | grep paa2img                      # present = you have the fork
```

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

`dayz-mod-pack.sh build --binarize-models` automates the recipe below: it creates a temporary sandbox and Wine
prefix (first run takes a while), converts every `.p3d`/`.rtm` in a staging copy of each addon (your sources stay
MLOD), builds and signs from the staging copy, and deletes the sandbox. It finds DayZ Tools and Proton under the Steam
root (override with `STEAM_ROOT`, `DAYZ_TOOLS`, `PROTON`) and fails with the binarize log if a model does not convert.
Tested with the one-triangle model above only.

armake2 only calls BI's `binarize.exe` (DayZ Tools, Steam app 830640) on Windows, so on Linux `.p3d`/`.rtm`
stay MLOD. Running the exe yourself under Proton works, with one trap. Wine maps `Z:` to `/`, and Binarize
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

## Uploading with `workshop`

Source: https://github.com/nozwock/steam-workshop-uploader (Rust, bundles Steamworks). The Steam client must
be running and logged in as an account that owns DayZ; the DayZ client app id is **221100**.

```sh
# first upload: creates the item and writes workshop.toml into the content folder
workshop create --app-id 221100 --content build/@MyMod --title "My Mod" \
    --ignore-file .workshopignore --glob '!*.biprivatekey' --visibility private -m "first upload"
cp build/@MyMod/workshop.toml workshop.toml && git add workshop.toml     # item id is not secret

# later: rebuild with the script (keeps workshop.toml), then
workshop update --content build/@MyMod --ignore-file .workshopignore --glob '!*.biprivatekey' -m "changelog"
```

- `workshop.toml` (`app_id`, `item_id`, `tags`) tells `update` which item to overwrite; it is never uploaded.
- The uploader makes a filtered staging copy first, honouring `.ignore`/`.gitignore`, `--ignore-file` and
  `--glob`. Globs are case-sensitive; a leading `!` excludes. `--no-prompt` disables interactive questions.
- Start with `--visibility private` (or `unlisted`), subscribe to the item with another account or check the
  Workshop page, then flip it public in Steam.
- Uploading publishes content to Steam and may be cached by clients; it is the user's decision. Run
  `check` and look at the content folder first; do not run `create`/`update` unprompted.
- Do not ship a `meta.cpp`: it is Workbench/Steam metadata, and the uploader does not need it.

## Pitfalls

- **Prefix vs script paths**: `CfgMods` `files[] = {"MyMod/scripts/3_Game"}` only resolves if the PBO
  prefix is `MyMod`. A wrong or missing prefix loads the PBO but compiles none of its scripts.
- **One key per mod family**: sign every PBO of a mod with the same key so one `.bikey` covers all.
- **Server mods vs client mods**: PBOs for `-servermod=` need no key on clients; `-mod=` mods do.
- **Case and separators**: PBO inner paths use `\`; `armake2 cat` needs `'scripts\5_Mission\x.c'`.
- **Large asset mods**: `build` loads files in memory; very large PBOs need RAM to match.
- **Testing**: boot the result with `testing/local-server.md` (`-mod=@MyMod`, copy `keys/MyMod.bikey`
  into the tree's `keys/`) and compare script module counts with vanilla before uploading.
