# Pack template

A small, valid content pack to copy. See `docs/making-packs.md` for what every field means.

1. Copy this folder to `packs/<your-pack-id>/` and set `id` in `pack.json` to the same name.
2. Tags: add your pack's tag (kind `pack`) and your topics (kind `topic`, `<area>.<topic>`) to `data/tags.json`, put the
   pack tag in `pack.json` under `tags`, and list each concept's topics. Give every item `tags`: one to three topics and the
   pack tag. The template uses the tag `my-first-pack` and the topics `accounts.passwords` and `accounts.mfa`; they are
   not in `data/tags.json`, so a copy placed in `packs/` fails until you register yours (the section "Tags" in
   `docs/making-packs.md` shows how).
3. Replace the domains, objectives, concepts, items and Codex entries with your own. `explain` and `references`
   are optional on any item (two items here show `references`).
4. List it in `data/tracks.json` (`"pack": "<your-pack-id>"`).
5. Check it: `validate-pack` (see `docs/making-packs.md`).

Everything in this folder, including these example questions, is free to reuse (CC BY 4.0, see `packs/LICENSE.md`).
