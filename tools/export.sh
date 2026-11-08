#!/usr/bin/env bash
# Build the browser version into dist/web/ (git-ignored) and dist/cybersec-terminal-web.zip.
#   tools/export.sh                              everything
#   tools/export.sh --without PACK [PACK ...]    leave packs out (folder names under packs/); those tracks
#                                                show as "coming soon". The zip gets a "-reduced" suffix.
# Godot: $GODOT if set, else nix-shell (NixOS), else `godot` on PATH. Needs Godot 4.6.3 and its web export
# templates (Editor > Manage Export Templates, or the nix steps below), once:
#   nix-build '<nixpkgs>' -A godot_4_6-export-templates-bin --no-out-link
#   ln -s <that path>/share/godot/export_templates/4.6.3.stable ~/.local/share/godot/export_templates/4.6.3.stable
# Needs bash and python3. See docs/sharing.md. Nothing is uploaded; GitHub Pages publishes via .github/workflows/pages.yml.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="4.6.3.stable"
TEMPLATES="$HOME/.local/share/godot/export_templates/$VERSION"

if [ ! -d "$TEMPLATES" ]; then
  echo "Godot export templates $VERSION are missing: $TEMPLATES" >&2
  echo "One-time setup is in the header of this script and in docs/sharing.md." >&2
  exit 1
fi

cd "$HERE"

SUFFIX=""
if [ "${1:-}" = "--without" ]; then
  shift
  [ "$#" -gt 0 ] || { echo "--without needs at least one pack folder name" >&2; exit 1; }
  FILTER=""
  for pack in "$@"; do
    [ -d "packs/$pack" ] || { echo "no such pack folder: packs/$pack" >&2; exit 1; }
    FILTER="packs/$pack/*, $FILTER"
  done
  cp export_presets.cfg export_presets.cfg.bak
  trap 'mv -f export_presets.cfg.bak export_presets.cfg' EXIT
  sed -i "s#exclude_filter=\"#exclude_filter=\"$FILTER#" export_presets.cfg
  SUFFIX="-reduced"
elif [ "$#" -gt 0 ]; then
  echo "usage: tools/export.sh [--without PACK ...]" >&2
  exit 1
fi

rm -rf dist
mkdir -p dist/web

run_godot() {
  if [ -n "${GODOT:-}" ]; then
    "$GODOT" --path "$HERE" --headless "$@" 2>&1
  elif command -v nix-shell >/dev/null 2>&1; then
    # %q keeps each argument one word through nix-shell's own shell.
    env -u LD_LIBRARY_PATH nix-shell -p godot --run "godot --path '$HERE' --headless $(printf '%q ' "$@")" 2>&1
  elif command -v godot >/dev/null 2>&1; then
    godot --path "$HERE" --headless "$@" 2>&1
  else
    echo "Godot not found: set GODOT=/path/to/godot, or put godot on PATH." >&2
    exit 1
  fi
}

# A fresh clone has no .godot/ class cache; importing first lets it build.
run_godot --import | grep -E "ERROR" || true

run_godot --export-release "Web" dist/web/index.html | grep -E "ERROR|DONE.*savepack" || true
[ -f dist/web/index.html ] || { echo "export failed: dist/web/index.html was not written" >&2; exit 1; }

python3 - "$HERE" "$SUFFIX" <<'PY'
import os, sys, zipfile
here = sys.argv[1]
suffix = sys.argv[2]
web_dir = os.path.join(here, "dist", "web")
# Godot's MIT terms want the notice to travel with every copy, so the build carries the licences.
extras = {
    "LICENSE.txt": os.path.join(here, "LICENSE"),
    "THIRD-PARTY.txt": os.path.join(here, "THIRD-PARTY.md"),
    "README.txt": os.path.join(here, "tools", "web-readme.txt"),
}
for name, src in extras.items():  # also served next to the page, e.g. .../LICENSE.txt
    with open(src, "rb") as f, open(os.path.join(web_dir, name), "wb") as out:
        out.write(f.read())
# The web build is a folder of files (index.html and friends) that must sit together on a web server.
web_zip = os.path.join(here, "dist", "cybersec-terminal-web%s.zip" % suffix)
with zipfile.ZipFile(web_zip, "w", zipfile.ZIP_DEFLATED) as z:
    for name in sorted(os.listdir(web_dir)):
        z.write(os.path.join(web_dir, name), name)
print("%s  %.1f MB" % (web_zip, os.path.getsize(web_zip) / 1e6))
PY
