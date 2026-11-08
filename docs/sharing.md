# Publishing the browser version

The game is published **only as a web page**, on GitHub Pages. Players open a link; nothing is installed. There are no
Windows or Linux builds. `tools/export.sh` uploads nothing; Pages publishes through `.github/workflows/pages.yml`.

## Build it locally

```
tools/export.sh                                       # everything
tools/export.sh --without linux-cli                               # leave a pack out ("-reduced" zip)
```

Output (git-ignored `dist/`): `dist/web/` (`index.html`, the engine files, the game data, `LICENSE.txt`,
`THIRD-PARTY.txt`, `README.txt`) and `dist/cybersec-terminal-web.zip` of the same, about 10.8 MB, for anyone who wants to
host it elsewhere. The export settings are the single "Web" preset in `export_presets.cfg` (single-threaded, so Pages
needs no special headers). Try it from `dist/web`: `python3 -m http.server 8765`, then open
http://localhost:8765/index.html (a page opened straight from disk will not work).

**One-time setup on this NixOS machine** (the script stops with a message if it is missing): the Godot export
templates, which must match the editor exactly (4.6.3.stable; nixpkgs has them as `godot_4_6-export-templates-bin`):

```
nix-build '<nixpkgs>' -A godot_4_6-export-templates-bin --no-out-link      # prints a store path
ln -s <that path>/share/godot/export_templates/4.6.3.stable ~/.local/share/godot/export_templates/4.6.3.stable
```

Elsewhere: Godot 4.6.3 and Editor > Manage Export Templates, then `GODOT=/path/to/godot tools/export.sh`. If Godot is
ever upgraded, update `4.6.3` in `.github/actions/setup-godot/action.yml`, `VERSION` in `tools/export.sh` and the
templates folder name.

## What the build contains

- All of `packs/`, `data/` and `assets/`, plus the game's scripts. Excluded by the preset: `tests/`, `tools/`, `docs/`,
  `addons/gut/`, `templates/`, `*.pdf` and `*.md`. (Non-Godot files such as the pack JSON are included by the preset's
  `include_filter`; a new top-level data folder must be added there.)
- No profiles, no personal paths, no email address.
- **Leaving a pack out** removes its folder from the build; `data/tracks.json` then shows that track as
  "coming soon" with no error. The GitHub workflow builds whatever is in the repository, so to keep a pack off the
  public site, keep it out of the public repository.

## In the browser

- Progress is saved in the browser (IndexedDB) per browser, per computer and per site address. Clearing the site's data
  erases it; there is no sync between devices. (Tested by hand: a profile survives a page reload.)
- The JSON cannot be edited in the web version; editing packs and rules needs the source and the Godot editor
  (`docs/making-packs.md`).
- The `quit` command saves and says to close the tab.
- The first load downloads about 10 MB (the 37 MB engine file compressed); later visits use the browser cache.
  Whether GitHub Pages compresses the `.wasm` file is not confirmed.

## GitHub Pages

`.github/workflows/pages.yml` runs on every push to `main` (or "Run workflow" in the Actions tab): it installs the
pinned Godot 4.6.3 and the web export templates (SHA-512 checked against Godot's published sums, cached), validates
every pack, runs `tools/export.sh` and deploys `dist/web`. `.github/workflows/ci.yml` runs the pack checks on pull
requests. It deploys from `main`, not from tags, because the `github-pages` environment only accepts the default branch.

**One-time setup in the new repository:** Settings > Pages > Build and deployment > Source: **GitHub Actions**. The site
is then at `https://0xbaadfade.github.io/cybersec-terminal/`.

**Not tested on GitHub itself:** the workflows were linted (actionlint) and their YAML parsed, but they have never run
(this machine cannot run Actions). Expect to fix something on the first push. If a run fails at "Download and verify",
check the Godot download URL and the checksum line first.
