#!/usr/bin/env bash
# Extract the code files (scripts, configs) of the installed vanilla game PBOs with armake2.
#
# usage: extract-dayz-sources.sh <DayZ-install-dir | mod-dir> <out-dir>
#   e.g. extract-dayz-sources.sh ~/.steam/debian-installation/steamapps/common/DayZ /tmp/dayz-sources
#   a Workshop mod dir (steamapps/workshop/content/221100/<id>, with an addons/ folder) works the same way
#
# Searches <install>/dta and <install>/Addons plus the DLC folders <install>/*/addons (case-insensitive).
# Workshop mods are symlinked into the install dir as @xxxx; find does not follow symlinks, so they are skipped.
# Only code is extracted: *.c *.cpp *.h *.hpp *.inc *.json *.cfg *.txt, and config.bin (derapified to config.cpp).
# Models, textures, sounds, layouts and shaders are never read. Files land in <out>/<pbo prefix>/<inner path>,
# e.g. prefix "scripts" -> <out>/scripts/3_Game/..., prefix "DZ\AI" -> <out>/DZ/AI/config.cpp.
# Needs armake2 on PATH. Write <out-dir> below /tmp or /var/tmp, not below $HOME.
set -eu
[ $# -eq 2 ] || { sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
install=$1 out=$2
command -v armake2 >/dev/null || { echo "armake2 not found on PATH" >&2; exit 1; }
[ -d "$install" ] || { echo "$install is not a directory" >&2; exit 1; }
mkdir -p "$out"
tmp=$(mktemp -d /tmp/dayz-extract.XXXXXX)
trap 'rm -rf "$tmp"' EXIT

find "$install" -maxdepth 2 -type d \( -name dta -o -iname addons \) -print0 | sort -z |
while IFS= read -r -d '' dir; do
  find "$dir" -maxdepth 1 -type f -name '*.pbo' -print0 | sort -z |
  while IFS= read -r -d '' pbo; do
    armake2 inspect "$pbo" > "$tmp/list" 2>/dev/null || { echo "skip (unreadable): $pbo" >&2; continue; }
    prefix=$(sed -n 's/^- prefix=//p' "$tmp/list" | tr -d '\r' | tr '\\' '/')
    [ -n "$prefix" ] || prefix=$(basename "$pbo" .pbo)
    # file rows: "<path>   <method> <orig> <packed>"; keep code files and config.bin
    sed -n '/^====/,$p' "$tmp/list" | sed 1d |
      sed -E 's/[[:space:]]+[0-9]+[[:space:]]+[0-9]+[[:space:]]+[0-9]+[[:space:]]*$//' |
      grep -iE '(\.(c|cpp|h|hpp|inc|json|cfg|txt)|(^|\\)config\.bin)$' > "$tmp/want" || true
    [ -s "$tmp/want" ] || continue
    n=0
    while IFS= read -r inner; do
      inner=${inner%$'\r'}
      rel=$(printf '%s' "$inner" | tr '\\' '/')
      dest="$out/$prefix/$rel"
      mkdir -p "$(dirname "$dest")"
      case $rel in
        *config.bin)
          rm -f "$tmp/config.bin"
          armake2 cat "$pbo" "$inner" "$tmp/config.bin" >/dev/null 2>&1 &&
            armake2 derapify -f "$tmp/config.bin" "${dest%.bin}.cpp" >/dev/null 2>&1 ||
            echo "derapify failed: $pbo $inner" >&2 ;;
        *) armake2 cat "$pbo" "$inner" "$dest" >/dev/null 2>&1 || echo "cat failed: $pbo $inner" >&2 ;;
      esac
      n=$((n + 1))
    done < "$tmp/want"
    echo "$n files  $prefix  <- ${pbo#"$install"/}"
  done
done
