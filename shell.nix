# Pins the Godot used by this project. Godot is not on PATH on this machine
# (NixOS); run.sh uses `nix-shell -p godot`, which resolves to the same build.
#   nix-shell shell.nix --run 'godot --version'     -> 4.6.3.stable
{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  name = "cert-terminal-godot";
  buildInputs = [ pkgs.godot ];
}
