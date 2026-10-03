#!/usr/bin/env bash
# Prepare a DayZ mod for the Steam Workshop with armake2: keys, PBOs, signatures, upload folder.
#
# Project layout (created by `init`, filled by `keygen` and `build`):
#   .dayzmod            MOD_NAME=MyMod (read by every command)
#   mod.cpp             mod metadata, copied to the content folder
#   src/<Addon>/        one folder per PBO: config.cpp, $PREFIX$, scripts/, data/ ...
#   static/             copied verbatim into the content folder (logos, README, ...)
#   keys/<Key>.bikey    PUBLIC key, safe to commit; shipped to server owners
#   secrets/            PRIVATE key (<Key>.biprivatekey). Git-ignored, never copied anywhere.
#   workshop.toml       written by `workshop create`; kept in git, copied into the content folder
#   build/@<MyMod>/     the Workshop content folder: addons/*.pbo + *.bisign, keys/, mod.cpp
#
# Usage: dayz-mod-pack.sh [-C <projectdir>] <command> [options]
#   init <ModName> [--servermod]
#                           create the folders, .gitignore, .workshopignore, mod.cpp stub; WORKSHOP_TAGS in
#                           .dayzmod defaults to "Mod" ("Mod Server" with --servermod)
#   keygen                  create secrets/<Key>.biprivatekey and keys/<Key>.bikey (refuses to overwrite)
#   build [--no-bin] [--v2] [--binarize-models]
#                           build+sign every src/<Addon>/ and assemble build/@<ModName>/
#                           --no-bin  pack without rapifying config.cpp (armake2 pack)
#                           --v2      sign with the older v2 signature instead of v3
#                           --binarize-models  convert .p3d/.rtm (MLOD -> ODOL) with BI's binarize.exe
#                                    from DayZ Tools, run under Proton in a tiny sandboxed Wine Z: drive
#                                    (Linux only; see systems/mod-packaging.md). Sources stay untouched.
#                                    Uses armake2's own --proton-binarize when the armake2 in PATH has it.
#   check                   verify nothing secret is tracked or staged, and the signatures verify
#   publish-hint            print the `workshop create` / `workshop update` commands
#
# Environment: ARMAKE2 (binary, default: the armake2 found in PATH), KEY_NAME (default: ModName),
#              WORKSHOP_APP_ID (default 221100, the DayZ client app),
#              DAYZ_TOOLS (DayZ Tools dir) and PROTON (Proton dir) for --binarize-models; both auto-detected.
# Nothing here talks to Steam: uploading stays a deliberate manual step.
set -euo pipefail

die() { echo "error: $*" >&2; exit 1; }
say() { printf '== %s\n' "$*"; }

PROJECT=.
if [ "${1:-}" = "-C" ]; then PROJECT=${2:?-C needs a directory}; shift 2; fi
CMD=${1:-}; [ $# -gt 0 ] && shift
[ -n "$CMD" ] || { sed -n '2,/^set -euo/p' "$0" | sed '$d;s/^# \{0,1\}//'; exit 2; }

ARMAKE2=${ARMAKE2:-armake2}
APP_ID=${WORKSHOP_APP_ID:-221100}

# Files that must never end up inside a PBO or the Workshop upload.
PBO_EXCLUDES=('*.psd' '*.xcf' '*.kra' '*.blend' '*.blend1' '*.bak' '*.tmp' '*.biprivatekey' 'Thumbs.db' '.DS_Store')

load_conf() {
    [ -f "$PROJECT/.dayzmod" ] || die "no $PROJECT/.dayzmod; run: $0 init <ModName>"
    # shellcheck disable=SC1091
    . "$PROJECT/.dayzmod"
    [ -n "${MOD_NAME:-}" ] || die ".dayzmod does not set MOD_NAME"
    KEY_NAME=${KEY_NAME:-$MOD_NAME}
    WORKSHOP_TAGS=${WORKSHOP_TAGS:-Mod}
    CONTENT="$PROJECT/build/@$MOD_NAME"
}

# Use the armake2 found in PATH first (or $ARMAKE2), then check what it can do:
#   HAS_FORK    the bzed fork (https://github.com/bzed/armake2): DayZ preprocessor fixes, $PREFIX$, paa2img
#   HAS_PROTON  the fork's --proton-binarize (binarize.exe under Proton); then --binarize-models uses it
need_armake2() {
    command -v "$ARMAKE2" >/dev/null 2>&1 || die "armake2 not found in PATH. Install the DayZ fork: git clone https://github.com/bzed/armake2 && cd armake2 && cargo build --release (then put target/release/armake2 in PATH), or set ARMAKE2=/path/to/armake2"
    local help; help=$("$ARMAKE2" --help 2>&1 || true)
    HAS_FORK=0; HAS_PROTON=0
    case "$help" in *paa2img*) HAS_FORK=1 ;; esac
    case "$help" in *proton-binarize*) HAS_PROTON=1 ;; esac
    [ "$HAS_FORK" = 1 ] || echo "warning: $(command -v "$ARMAKE2") looks like upstream armake2, not the bzed fork (https://github.com/bzed/armake2); DayZ configs may fail to build" >&2
}

# --- --binarize-models: BI's binarize.exe under Proton -----------------------------------------
# Wine's Z: maps to / and binarize.exe walks directory trees from the drive root, which spins for
# minutes on a real home directory. So Z: is replaced by a sandbox holding only Binarize and the files.
find_steam_common() {
    local r
    for r in "${STEAM_ROOT:-}" "$HOME/.steam/debian-installation" "$HOME/.steam/steam" "$HOME/.local/share/Steam"; do
        [ -n "$r" ] && [ -d "$r/steamapps/common" ] && { echo "$r"; return 0; }
    done
    return 1
}

BIN_W=""   # sandbox dir, created on first use
setup_binarize() {
    [ -n "$BIN_W" ] && return 0
    local steam tools proton p
    steam=$(find_steam_common) || die "no Steam install found (set STEAM_ROOT) for --binarize-models"
    tools=${DAYZ_TOOLS:-$steam/steamapps/common/DayZ Tools}
    [ -f "$tools/Bin/Binarize/binarize.exe" ] || die "binarize.exe not found in '$tools' (install DayZ Tools, Steam app 830640, or set DAYZ_TOOLS)"
    proton=${PROTON:-}
    if [ -z "$proton" ]; then
        for p in "Proton Hotfix" "Proton - Experimental" "Proton Experimental" Proton*; do
            [ -x "$steam/steamapps/common/$p/proton" ] && { proton="$steam/steamapps/common/$p"; break; }
        done
    fi
    [ -x "$proton/proton" ] || die "no Proton found under $steam/steamapps/common (install one in Steam, or set PROTON)"
    BIN_W=$(mktemp -d "${TMPDIR:-/tmp}/dayz-binarize.XXXXXX")
    BIN_PROTON="$proton/proton"; BIN_STEAM=$steam
    BIN_PROTONDIR=$proton
    # wineserver keeps the prefix busy after the last binarize run; stop it before deleting the sandbox
    trap 'WINEPREFIX="$BIN_W/prefix/pfx" "$BIN_PROTONDIR/files/bin/wineserver" -k >/dev/null 2>&1; sleep 1; rm -rf "$BIN_W"' EXIT
    mkdir -p "$BIN_W/prefix" "$BIN_W/stage" "$BIN_W/out"
    cp -r "$tools/Bin/Binarize" "$BIN_W/Binarize"
    export STEAM_COMPAT_CLIENT_INSTALL_PATH=$steam STEAM_COMPAT_DATA_PATH=$BIN_W/prefix SteamAppId=830640 SteamGameId=830640 STEAM_COMPAT_APP_ID=830640
    say "creating a Wine prefix for binarize.exe (first run takes a while)"
    # the first proton run creates the prefix; run something trivial, then confine Z:
    timeout 300 "$BIN_PROTON" run cmd.exe /c exit >"$BIN_W/prefix-init.log" 2>&1 || die "Proton prefix creation failed, see $BIN_W/prefix-init.log"
    [ -d "$BIN_W/prefix/pfx/dosdevices" ] || die "Proton did not create a prefix in $BIN_W/prefix"
    ln -sfn "$BIN_W" "$BIN_W/prefix/pfx/dosdevices/z:"
}

# winpath <path under $BIN_W> -> Z:\... (Z: is the sandbox)
winpath() { local r=${1#"$BIN_W"/}; printf 'Z:\\%s' "${r//\//\\}"; }

# stage_models <addon dir> <addon name>: copy the addon to the sandbox, convert every .p3d/.rtm there.
stage_models() {
    setup_binarize
    local src=$1 name=$2 stage="$BIN_W/stage/$2" f dir base n=0 out
    rm -rf "$stage"; cp -a "$src" "$stage"
    while IFS= read -r -d '' f; do
        dir=$(dirname "$f"); base=$(basename "$f"); n=$((n+1)); out="$BIN_W/out/$n"
        mkdir -p "$out"
        ( cd "$BIN_W/Binarize" && timeout 600 "$BIN_PROTON" run ./binarize.exe -norecurse -always -silent -maxProcesses=0 \
            "$(winpath "$dir")" "$(winpath "$out")" "$base" ) >"$out/log" 2>&1 \
            || { tail -5 "$out/log" >&2; die "binarize.exe failed for ${f#"$stage"/} (see above)"; }
        [ -s "$out/$base" ] || die "binarize.exe produced no output for ${f#"$stage"/} (models with textures/materials may need a P: drive; see systems/mod-packaging.md)"
        cp "$out/$base" "$f"
    done < <(find "$stage" -type f \( -iname '*.p3d' -o -iname '*.rtm' \) -print0)
    echo "   binarized $n model/animation file(s) in $name" >&2
    printf '%s' "$stage"
}

cmd_init() {
    local name=${1:?usage: init <ModName> [--servermod]} tags="Mod"
    [ "${2:-}" = "--servermod" ] && tags="Mod Server"
    case "$name" in *[!A-Za-z0-9_]*|"") die "ModName may only contain letters, digits and _ (it becomes the key name and the PBO prefix)";; esac
    mkdir -p "$PROJECT/src" "$PROJECT/keys" "$PROJECT/secrets" "$PROJECT/static"
    # WORKSHOP_TAGS: Steam Workshop tags for app 221100. "Mod" is required; "Server" marks server-side content.
    [ -f "$PROJECT/.dayzmod" ] || printf 'MOD_NAME=%s\nWORKSHOP_TAGS="%s"\n' "$name" "$tags" > "$PROJECT/.dayzmod"

    # .gitignore: append only the lines that are missing, never rewrite the user's file.
    touch "$PROJECT/.gitignore"
    for line in 'secrets/' '*.biprivatekey' 'build/'; do
        grep -qxF "$line" "$PROJECT/.gitignore" || echo "$line" >> "$PROJECT/.gitignore"
    done
    # Belt and braces for the uploader: pass this with --ignore-file (see publish-hint).
    [ -f "$PROJECT/.workshopignore" ] || printf '*.biprivatekey\nsecrets/\n*.psd\n*.xcf\n*.kra\n*.blend\n*.blend1\n.git*\n' > "$PROJECT/.workshopignore"
    # A private key left in the project root by mistake should never be committed either.
    # Fields seen in real Workshop mods (CF and others). No app id here: the app id lives in workshop.toml / --app-id.
    # picture/logo* are paths INSIDE a PBO (prefix-relative, e.g. "MyMod/gui/logo.paa"); leave empty until you ship one.
    [ -f "$PROJECT/mod.cpp" ] || cat > "$PROJECT/mod.cpp" <<EOF
name = "$name";
picture = "";
logo = "";
logoSmall = "";
logoOver = "";
tooltip = "$name";
overview = "";
action = "";
author = "";
authorID = "";
version = "1.0";
EOF
    local addon
    for addon in "$PROJECT"/src/*/; do
        [ -d "$addon" ] || continue
        [ -f "$addon/\$PREFIX\$" ] || printf '%s\n' "$(basename "$addon")" > "$addon/\$PREFIX\$"
    done
    say "initialised $name in $PROJECT; put each addon in src/<Addon>/ (config.cpp + scripts/ + ...)"
    say "next: $0 keygen"
}

cmd_keygen() {
    load_conf; need_armake2
    local priv="$PROJECT/secrets/$KEY_NAME.biprivatekey" pub="$PROJECT/keys/$KEY_NAME.bikey"
    if [ -e "$priv" ] || [ -e "$pub" ]; then
        die "key $KEY_NAME already exists. Replacing it makes every server owner install a new .bikey and breaks existing signatures; delete both files by hand if you really mean it."
    fi
    git -C "$PROJECT" check-ignore -q "secrets/$KEY_NAME.biprivatekey" 2>/dev/null \
        || [ ! -d "$PROJECT/.git" ] \
        || die "secrets/ is not git-ignored; run init (or add 'secrets/' and '*.biprivatekey' to .gitignore) first"
    mkdir -p "$PROJECT/secrets" "$PROJECT/keys"
    ( umask 077; "$ARMAKE2" keygen "$PROJECT/secrets/$KEY_NAME" )
    mv "$PROJECT/secrets/$KEY_NAME.bikey" "$pub"
    chmod 600 "$priv"
    say "private key: $priv  (BACK THIS UP outside the repo; losing it means a new key and new .bikey for all servers)"
    say "public key:  $pub  (commit this; server owners copy it into their keys/ folder)"
}

# meta.cpp is what the official DayZ Publisher adds to the upload (protocol, publishedid, name, timestamp).
# The `workshop` uploader does not, so we write it. Before the item exists (no workshop.toml / item_id) the
# publishedid is 0 (0 = unpublished), which is what the Windows tools upload on a first publish. That works for
# server mods but NOT for client mods, so a client mod must be updated with the real id before it is made public;
# once workshop.toml holds the item_id, every build writes the real id.
# timestamp = .NET DateTime.ToBinary() of the UTC time: (unix + 62135596800) * 1e7 + 2^62 (checked against CF's meta.cpp).
write_meta() {
    local toml="$CONTENT/workshop.toml" id=0
    if [ -f "$toml" ]; then
        id=$(sed -n 's/^ *item_id *= *\([0-9][0-9]*\).*/\1/p' "$toml" | head -1)
        id=${id:-0}
    fi
    printf 'protocol = 1;\npublishedid = %s;\nname = "%s";\ntimestamp = %s;\n' \
        "$id" "$MOD_NAME" "$(( ($(date -u +%s) + 62135596800) * 10000000 + 4611686018427387904 ))" > "$CONTENT/meta.cpp"
    if [ "$id" = 0 ]; then say "meta.cpp written with publishedid = 0 (item not created yet)"
    else say "meta.cpp written for Workshop item $id"; fi
}

cmd_build() {
    local mode=build ver=() a binmodels=0
    for a in "$@"; do
        case "$a" in
            --no-bin) mode=pack ;;
            --v2) ver=(--v2) ;;
            --binarize-models) binmodels=1 ;;
            *) die "unknown option: $a" ;;
        esac
    done
    load_conf; need_armake2
    local priv="$PROJECT/secrets/$KEY_NAME.biprivatekey"
    [ -f "$priv" ] || die "no private key at $priv; run: $0 keygen"
    local addons=()
    for a in "$PROJECT"/src/*/; do [ -d "$a" ] && addons+=("${a%/}"); done
    [ ${#addons[@]} -gt 0 ] || die "no addon folders in src/ (expected src/<Addon>/config.cpp)"

    # Rebuild addons/ and keys/ from scratch, but keep workshop.toml and anything else the uploader owns.
    rm -rf "$CONTENT/addons" "$CONTENT/keys"
    mkdir -p "$CONTENT/addons" "$CONTENT/keys"

    local excl=() e
    for e in "${PBO_EXCLUDES[@]}"; do excl+=(-x "$e"); done

    local dir addon pbo srcdir wq
    for dir in "${addons[@]}"; do
        addon=$(basename "$dir")
        [ -f "$dir/config.cpp" ] || echo "warning: src/$addon has no config.cpp; DayZ will not load it as an addon" >&2
        [ -f "$dir/\$PREFIX\$" ] || echo "note: src/$addon has no \$PREFIX\$; armake2 falls back to the folder name '$addon' as prefix" >&2
        pbo="$CONTENT/addons/$addon.pbo"
        srcdir=$dir; wq=()
        if [ "$binmodels" = 1 ]; then
            [ "$mode" = build ] || die "--binarize-models cannot be combined with --no-bin"
            if [ "$HAS_PROTON" = 1 ]; then
                wq=(--proton-binarize)      # armake2 itself runs binarize.exe under Proton
            else
                echo "note: $(command -v "$ARMAKE2") has no --proton-binarize (update to the bzed fork); using this script's own Proton staging" >&2
                setup_binarize      # in this shell, not in the $(...) below, so BIN_W and the cleanup trap survive
                srcdir=$(stage_models "$dir" "$addon"); wq=(-w non-windows-binarization)   # models were converted above
            fi
        fi
        say "$mode $addon"
        # Absolute include path so `#include "\MyMod\..."` style includes resolve from the project's src/.
        if [ "$mode" = build ]; then
            "$ARMAKE2" build -f -i "$PROJECT/src" -e product=dayz "${wq[@]}" "${excl[@]}" "$srcdir" "$pbo"
        else
            "$ARMAKE2" pack -f -e product=dayz "${excl[@]}" "$srcdir" "$pbo"
        fi
        "$ARMAKE2" sign -f "${ver[@]}" "$priv" "$pbo"
        "$ARMAKE2" verify "$PROJECT/keys/$KEY_NAME.bikey" "$pbo" "$pbo.$KEY_NAME.bisign" \
            || die "signature of $addon.pbo does not verify against keys/$KEY_NAME.bikey"
    done

    cp "$PROJECT/keys/$KEY_NAME.bikey" "$CONTENT/keys/"
    [ -f "$PROJECT/mod.cpp" ] && cp "$PROJECT/mod.cpp" "$CONTENT/mod.cpp"
    [ -f "$PROJECT/workshop.toml" ] && [ ! -f "$CONTENT/workshop.toml" ] && cp "$PROJECT/workshop.toml" "$CONTENT/workshop.toml"
    if [ -d "$PROJECT/static" ]; then cp -a "$PROJECT/static/." "$CONTENT/"; fi
    write_meta

    # The one rule that matters: the private key must not be anywhere under the upload folder.
    if find "$CONTENT" -name '*.biprivatekey' | grep -q .; then
        die "a .biprivatekey is inside $CONTENT; refusing to continue"
    fi
    say "content folder ready: $CONTENT"
    ( cd "$CONTENT" && find . -type f | sort | sed 's|^\./|   |' )
}

# Tags seen on the 438 DayZ Workshop items checked (Steam API): every item has Mod; Server marks server-side content.
KNOWN_TAGS="Mod Server Mechanics Equipment Environment Props Character Terrain Sound Economy Vehicle Animation Weapon"
check_tags() {
    local t ok=1 hasmod=0
    for t in $WORKSHOP_TAGS; do
        [ "$t" = Mod ] && hasmod=1
        case " $KNOWN_TAGS " in *" $t "*) ;; *) echo "warn: tag '$t' is not one of the tags seen on DayZ items ($KNOWN_TAGS)"; ;; esac
        [ "$t" = "Tag Review" ] && echo "warn: 'Tag Review' is a moderation tag; do not set it yourself"
    done
    if [ "$hasmod" = 1 ]; then echo "ok: tags: $WORKSHOP_TAGS"; else echo "FAIL: WORKSHOP_TAGS must contain Mod (the Publisher rejects PBOs without it)" >&2; return 1; fi
}

cmd_check() {
    load_conf; need_armake2
    local bad=0 f
    if [ -d "$PROJECT/.git" ] || git -C "$PROJECT" rev-parse --git-dir >/dev/null 2>&1; then
        if git -C "$PROJECT" ls-files | grep -q 'biprivatekey'; then
            echo "FAIL: a .biprivatekey is tracked by git:" >&2
            git -C "$PROJECT" ls-files | grep 'biprivatekey' >&2; bad=1
        else echo "ok: no private key tracked by git"; fi
        if git -C "$PROJECT" log --all --name-only --format= 2>/dev/null | grep -q 'biprivatekey'; then
            echo "FAIL: a .biprivatekey exists in git history; treat the key as leaked and rotate it" >&2; bad=1
        else echo "ok: no private key in git history"; fi
        git -C "$PROJECT" check-ignore -q "secrets/$KEY_NAME.biprivatekey" \
            && echo "ok: secrets/ is git-ignored" || { echo "FAIL: secrets/$KEY_NAME.biprivatekey is not git-ignored" >&2; bad=1; }
    else
        echo "note: $PROJECT is not a git repository; skipping git checks"
    fi
    if find "$CONTENT" -name '*.biprivatekey' 2>/dev/null | grep -q .; then
        echo "FAIL: private key inside the content folder" >&2; bad=1
    fi
    # Rules the official Publisher enforces (strings in Publisher.exe): addons/ in the root, PBOs only under addons/.
    if [ -d "$CONTENT" ]; then
        if [ -d "$CONTENT/addons" ]; then echo "ok: addons/ is in the content root"; else echo "FAIL: no addons/ folder in the content root" >&2; bad=1; fi
        if find "$CONTENT" -iname '*.pbo' -not -ipath "$CONTENT/addons/*" | grep -q .; then
            echo "FAIL: .pbo files outside addons/" >&2; bad=1; fi
        if [ -f "$CONTENT/mod.cpp" ] && grep -q '^ *name *=' "$CONTENT/mod.cpp"; then echo "ok: mod.cpp has a name"
        else echo "warn: no mod.cpp with a name in the content folder (optional, but the launcher shows it)"; fi
        if [ ! -f "$CONTENT/meta.cpp" ]; then echo "warn: no meta.cpp; run build"
        elif grep -q 'publishedid *= *0;' "$CONTENT/meta.cpp" && [ -f "$CONTENT/workshop.toml" ]; then
            echo "warn: meta.cpp still has publishedid = 0 but workshop.toml exists; run build again"; fi
    fi
    check_tags || bad=1
    for f in "$CONTENT"/addons/*.pbo; do
        [ -f "$f" ] || { echo "note: nothing built yet (run build)"; break; }
        "$ARMAKE2" verify "$PROJECT/keys/$KEY_NAME.bikey" "$f" "$f.$KEY_NAME.bisign" >/dev/null \
            && echo "ok: $(basename "$f") signature verifies" || { echo "FAIL: $(basename "$f") signature" >&2; bad=1; }
    done
    [ "$bad" -eq 0 ] || exit 1
}

cmd_publish_hint() {
    load_conf
    local tagargs="" t
    for t in $WORKSHOP_TAGS; do tagargs="$tagargs -t '$t'"; done
    cat <<EOF
Upload needs the Steam client running and logged in as the account that owns DayZ (app $APP_ID).
It is a deliberate manual step; review the content folder first:  $CONTENT

The app id ($APP_ID) is NOT part of mod.cpp: it is passed here and stored in workshop.toml.

First upload (creates the item and writes $CONTENT/workshop.toml; copy it to $PROJECT/workshop.toml and commit it).
The first upload carries a meta.cpp with publishedid = 0 (the item id does not exist before it), exactly like the Windows
tools; that is broken for client mods (fine for servermods). So the item is created private: afterwards run build
again (it writes the real id from workshop.toml into meta.cpp), publish that with the update command below, and
only then make the item public in Steam:
  workshop create --app-id $APP_ID --content "$CONTENT" --title "$MOD_NAME" \\
      --ignore-file "$PROJECT/.workshopignore" --glob '!*.biprivatekey' --visibility private$tagargs -m "first upload"

Tags ($WORKSHOP_TAGS) are stored in workshop.toml by create; update reuses them (Steam drops tags that are not sent).
Updates (item id comes from workshop.toml in the content folder):
  workshop update --content "$CONTENT" --ignore-file "$PROJECT/.workshopignore" --glob '!*.biprivatekey' -m "changelog"
EOF
}

case "$CMD" in
    init) cmd_init "$@" ;;
    keygen) cmd_keygen ;;
    build) cmd_build "$@" ;;
    check) cmd_check ;;
    publish-hint) cmd_publish_hint ;;
    *) die "unknown command: $CMD (init, keygen, build, check, publish-hint)" ;;
esac
