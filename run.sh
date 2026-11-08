#!/usr/bin/env bash
# Thin wrapper around `nix-shell -p godot` for the common invocations.
# Godot is not on PATH on this machine (NixOS). Every invocation clears
# LD_LIBRARY_PATH: the user's shell exports one that points at an alsa-lib
# built against a newer glibc than Godot's nix closure, and the load dies with
# "GLIBC_2.43 not found".
#
# Usage:
#   ./run.sh game [-- ...]            play (accepts: -- --profiles-dir DIR)
#   ./run.sh editor                   open the Godot editor
#   ./run.sh import                   (re)build the class cache; run after adding a class_name script
#   ./run.sh test [script_name]       the GUT suite, headless; exit 0 iff all pass
#   ./run.sh validate-pack [DIR]      check a content pack (default: every pack in packs/)
#   ./run.sh headless-check           boot and quit
#   ./run.sh capture out.png [--lines "new dana;status"]   render the terminal off-screen to a PNG
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

run_godot() {
  env -u LD_LIBRARY_PATH nix-shell -p godot --run "godot --path '$HERE' $*"
}

cmd="${1:-}"
shift || true

case "$cmd" in
  game)
    run_godot "$*"
    ;;
  editor)
    run_godot "-e"
    ;;
  import)
    run_godot "--headless --import"
    ;;
  test)
    if [ -n "${1:-}" ]; then
      run_godot "--headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gselect=$1 -gexit"
    else
      run_godot "--headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit"
    fi
    ;;
  validate-pack)
    run_godot "--headless -s res://tools/validate_pack.gd -- ${1:-}"
    ;;
  headless-check)
    run_godot "--headless --quit"
    ;;
  capture)
    out="$1"; shift
    # %q-quote the rest: they pass through nix-shell's own shell, and --lines
    # values contain ';'.
    extra="$(printf '%q ' "$@")"
    env -u LD_LIBRARY_PATH nix-shell -p godot xorg.xorgserver xvfb-run mesa --run \
      "xvfb-run -a -s '-screen 0 1280x720x24' godot --path '$HERE' --rendering-driver opengl3 --resolution 1280x720 res://tools/capture.tscn -- --out '$out' $extra"
    ;;
  *)
    echo "usage: $0 {game|editor|import|test [script]|validate-pack [dir]|headless-check|capture <out.png> [args]}" >&2
    exit 1
    ;;
esac
