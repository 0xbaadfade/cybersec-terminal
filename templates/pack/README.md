# Pack template

A small, valid content pack to copy. See `docs/making-packs.md` for what every field means.

1. Copy this folder to `packs/<your-pack-id>/` and set `id` in `pack.json` to the same name.
2. Replace the domains, objectives, concepts, items and Codex entries with your own. `explain` and `references`
   are optional on any item (two items here show `references`).
3. List it in `data/tracks.json` (`"pack": "<your-pack-id>"`).
4. Check it: `validate-pack` (see `docs/making-packs.md`).

Everything in this folder, including these example questions, is free to reuse (CC BY 4.0, see `packs/LICENSE.md`).
