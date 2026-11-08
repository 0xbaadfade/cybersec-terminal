# Making and tuning content

Everything a learner sees is data. A **pack** is a folder of JSON; the **rules** and the **skill tree** are two more
JSON files. You never need to touch the code to add a certification, change an XP rate or reshape the tree.

You do need to run the game from source for this: the published web version has its data built in and cannot be
edited. Install Godot 4.6.3 (https://godotengine.org/), open `project.godot`, press F5.

## A pack

Start from `templates/pack/`: copy it to `packs/<your-pack-id>/`.

```
packs/<pack-id>/
  pack.json      title, exam settings, domains, objectives and concepts
  items/         one or more .json files, each an array of items (any file names)
  codex.json     optional: a definition for each concept, shown in the Codex
```

### The least a pack needs

- `pack.json` with `id`, `title`, `short`, `version`, at least one domain and one objective (with at least one concept).
- One `items/*.json` file with at least one item.
- Nothing else. `codex.json`, the `exam` block, `explain` and `references` are optional. A concept with fewer than 3
  items is reported as a gap (a warning), and a pack with no `exam` block simply has no full-exam row.

### `pack.json`

| field | meaning |
|---|---|
| `id`, `title`, `short` | the pack's name (`short` is the label on narrow screens). Text, all required |
| `version` | a whole number, 1 or more |
| `exam` | optional exam block: `questions`, `minutes`, and a pass mark, either `pass_percent` (1 to 100) or `pass_score` inside `score_range`, never both |
| `domains` | list of `{id, title, weight}`; weights say how much of an exam each domain takes |
| `objectives` | list of `{id, title, domain, concepts}`; `domain` names a domain id |
| concepts | each `{id, title}`. **A concept id must start with its objective id and a dot**: objective `1.1` owns `1.1.passwords` |

A **concept** is the smallest thing the game tracks mastery for. Every item names the concepts it tests, and the map,
the spaced-repetition schedule and the skill tree's unlock percentages all key off them.

### Items

Every item has: `id` (unique in the pack), `type`, `concept_ids` (one or more, all defined in `pack.json`),
`difficulty` (1, 2 or 3), `source` (`hand` or `ai`), `reviewed` (true or false) and `stem` (the question).

Two fields are **optional**:

- **`explain`**: text shown after the learner answers, right or wrong. Leave it out and the learner sees only the
  result, the right answer and any per-option `why`. `validate-pack` notes how many items have none ("note: 3 of 40
  items have no explanation") but does not fail. If you include it, it must be text.
- **`references`**: where to read more, shown after the explanation as a "References:" list. A list of up to 8 entries;
  each is a text line or an object with a `title` and an optional `url` (it must start with `http://` or `https://`):

  ```json
  "references": [
    "NIST SP 800-63B, section 5.1.1",
    { "title": "OWASP Password Storage Cheat Sheet", "url": "https://cheatsheetseries.owasp.org/" }
  ]
  ```

  They are shown as plain text (the web address is not clickable; players can copy it). A malformed entry fails
  `validate-pack` with a message saying which item.

The per-option `why` (the reason a wrong option is wrong) was always optional and is unchanged. In the richer item
types (`match`, `order`, `evidence`) the explanations *inside* the item, on each pair, step or flaw, are required: they
are what the item teaches.

`source` and `reviewed` are honest labels: items made with AI help and not yet checked by a person should say
`"source": "ai", "reviewed": false`. Unreviewed AI items are served with lower priority.

The two simplest types, used by `templates/pack/`:

- **`mcq`**: `options` is a list of `{id, text, why}` (`why` explains a wrong option), `answer` is `["b"]`.
- **`multi`** ("select TWO"): same shape, `answer` lists several option ids, e.g. `["a", "c"]`. Partial credit.

The richer types (`evidence`, `terminal`, `match`, `order`) are not documented here yet. `packs/linux-cli/` and
`packs/windows-cli/` show `terminal` items and their simulated labs in working form (`labs/`, `tools.json`). Write `mcq` and `multi` items first; they are enough for a useful pack.

### Check it

```
godot --headless --path . -s res://tools/validate_pack.gd -- res://packs/<pack-id>
```

(On the maintainer's NixOS machine: `./run.sh validate-pack res://packs/<pack-id>`.) It prints a report and exits
with an error if the pack is broken. A concept with fewer than 3 items is reported as a gap, a warning only.
With no folder given it checks every pack and `data/tracks.json`.

### Put it in the game

Add the pack to a section of `data/tracks.json`, using the folder name as `pack`:

```json
{ "id": "my-first-pack", "title": "My First Pack", "pack": "my-first-pack" }
```

A track with no `requires` is open from the start. A track listed without a `pack` shows as "coming soon". A track
may also have:

- `requires`: a list of `{"track": "<id>", "percent": 60}` (that share of the other track's concepts known) or
  `{"track": "<id>", "exam": true}` (that track's exam passed; the pack must have a `pass_percent`);
- `price`: Cycles (the in-game currency) to open it;
- `kind: "stub"`: a placeholder that counts as complete (used for Foundations).

## The rules: `data/rules.json`

Engine numbers, not content. Change a value and restart.

| key | controls |
|---|---|
| `round_size`, `max_new_concepts_per_round` | questions per round; how many new concepts one round may introduce |
| `xp_per_difficulty` | XP for an easy, medium, hard question |
| `streak_bonus_per_step`, `streak_bonus_cap` | bonus per correct answer in a row, and its ceiling |
| `trace` | the pressure meter: `miss_full`, `relief_on_correct`, `limit` |
| `box_interval_days`, `requeue_gap` | spaced repetition: days until a concept is due, per Leitner box; `[min, max]` questions later that a missed item comes back within the round |
| `unlock_known_fraction` | in a pack's map, the share of one node's concepts that must be known before the next node in that domain opens |
| `auto_advance_correct` | whether a fully correct multiple-choice answer moves straight on to the next question without pressing Enter |
| `terminal`, `evidence` | settings for terminal missions and evidence hunts |
| `ranks` | `[name, XP needed]` pairs. A pack may override them in its own `pack.json` |
| `economy` | Cycles: output per minute by mastery box, the stale and repeat percentages, the idle cap, the first-exam bonus |
| `perks` | the shop: each perk's title, kind, base, levels, base cost and cost growth |

The game checks the file when it loads and reports a bad entry rather than silently ignoring it. These numbers are
starting guesses; adjust them to your learners.

## Colours

The terminal colours are constants in `src/view/term_theme.gd` (`BG`, `TEXT`, `DIM`, `ACCENT`, `ERROR`, `OK`, `RULE`).
Edit them there for now. Moving them into a JSON file is a planned change.
