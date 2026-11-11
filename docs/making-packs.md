# Making and tuning content

Everything a learner sees is data. A **pack** is a folder of JSON; the **rules** and the **skill tree** are two more
JSON files. You never need to touch the code to add a certification, change an XP rate or reshape the tree.

You do need to run the game from source for this: the published web version has its data built in and cannot be
edited. Install Godot 4.6.3 (https://godotengine.org/), open `project.godot`, press F5.

## A pack

Start from `templates/pack/`: copy it to `packs/<your-pack-id>/`.

```
packs/<pack-id>/
  pack.json      title, the pack's tag, exam settings, domains, objectives and concepts (each concept lists topics)
  items/         one or more .json files, each an array of items (any file names)
  codex.json     optional: a definition for each concept, shown in the Codex
data/tags.json   the one list of tags (topics, packs, flags) that items and packs may use
bank/items/      optional: questions that more than one pack shows (see "Tags")
```

Questions are not owned by a pack. Each item carries **tags** that say what it teaches and which packs show it, so one
question can appear in several packs (a WPA3-SAE question in a wireless pack and in a Security+ pack) and answering it
counts in all of them. The section "Tags" below is the part to read before you write questions.

### The least a pack needs

- `pack.json` with `id`, `title`, `short`, `version`, `tags` (your pack's tag), at least one domain and one objective
  (with at least one concept, each listing its `topics`).
- Your pack's tag and your topics added to `data/tags.json` (see "Tags").
- One `items/*.json` file with at least one item.
- Nothing else. `codex.json`, the `exam` block, `explain` and `references` are optional. A concept with fewer than 3
  items is reported as a gap (a warning), and a pack with no `exam` block simply has no full-exam row.

### `pack.json`

| field | meaning |
|---|---|
| `id`, `title`, `short` | the pack's name (`short` is the label on narrow screens). Text, all required |
| `version` | a whole number, 1 or more |
| `tags` | the pack's tag or tags, each a `pack` tag from `data/tags.json` (usually one, the same as the pack id). The pack shows every item that carries **any** of them |
| `exam` | optional exam block: `questions`, `minutes`, and a pass mark, either `pass_percent` (1 to 100) or `pass_score` inside `score_range`, never both |
| `domains` | list of `{id, title, weight}`; weights say how much of an exam each domain takes |
| `objectives` | list of `{id, title, domain, concepts}`; `domain` names a domain id |
| concepts | each `{id, title, topics}`; `topics` lists one or more topic tags from `data/tags.json`. **A concept id must start with its objective id and a dot**: objective `1.1` owns `1.1.passwords` |

A **topic** is the smallest thing the game tracks mastery for. A **concept** is where a topic sits in your pack's layout:
an item is in every concept of the pack that lists one of the item's topics. The map, the spaced-repetition schedule and
the skill tree's unlock percentages key off topics, so mastery of a topic carries over to every pack that uses it.

### Items

Every item has: `id` (unique across the game), `type`, `tags` (see below), `difficulty` (1, 2 or 3) and `stem` (the
question). The old `concept_ids` key is gone: `validate-pack` rejects it and says to use `tags`. An optional `reviewed_by` (`human` or `ai`) says who has reviewed the item.

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

`reviewed_by` is an honest label: leave it out unless someone has actually checked the item. `"human"` means the
maintainer checked it against a source, `"ai"` that an AI tool did. When the game builds a round it serves human-reviewed items
first, then AI-reviewed, then the rest. The older `source` and `reviewed` keys are gone: `validate-pack` rejects them.
`CONTENT-STANDARDS.md` (at the top of the repository) says what review means, who may set it, and what makes a good item.

The two simplest types, used by `templates/pack/`:

- **`mcq`**: `options` is a list of `{id, text, why}` (`why` explains a wrong option), `answer` is `["b"]`.
- **`multi`** ("select TWO"): same shape, `answer` lists several option ids, e.g. `["a", "c"]`. Partial credit.

The richer types (`evidence`, `terminal`, `match`, `order`) are not documented here yet. `packs/linux-cli/` and
`packs/windows-cli/` show `terminal` items and their simulated labs in working form (`labs/`, `tools.json`). Write `mcq` and `multi` items first; they are enough for a useful pack.

### Tags

An item's `tags` is one list that answers "what is this question about, and which packs is it for". Every tag must be listed
in `data/tags.json`, which gives each a `kind`; `validate-pack` rejects a tag that is not there (so `sae`, `wpa3-sae` and
`wpa3` cannot drift apart as three names for one subject).

| kind | looks like | what it means |
|---|---|---|
| `topic` | `wireless.sae`, `crypto.hashing` | what the question teaches; the id is `<area>.<topic>`. Mastery, scheduling and skill-tree progress are tracked per topic |
| `pack` | `sy0-701`, `wireless-security`, `linux-cli` | which pack the question is for |
| `flag` | `public` | says something about the item, not its subject: `public` means it may ship in the public repository |

Rules for one item (all checked): **one to three topics**, **at least one pack tag**, **at most eight tags** in all. A pack
shows an item only if one of its concepts lists one of the item's topics; if none does, no round can ask it (an error for an
item in the pack's own `items/`, a warning for a bank item, since another pack may show it).

*Simple: one topic, one pack.*

```json
{
  "id": "pw-101", "type": "mcq", "difficulty": 1,
  "tags": ["crypto.hashing", "my-first-pack"],
  "stem": "Which property makes a cryptographic hash suited to storing passwords?",
  "options": [
    { "id": "a", "text": "It is one-way" },
    { "id": "b", "text": "It can be reversed with the right key", "why": "A scheme with a key is encryption, not hashing." },
    { "id": "c", "text": "It makes every password the same length", "why": "Fixed output length is a side effect, not the reason." }
  ],
  "answer": ["a"]
}
```

*Expansive: two topics, two packs.* It shows up in both packs, and answering it counts for both topics.

```json
{
  "id": "wifi-101", "type": "mcq", "difficulty": 2,
  "tags": ["wireless.sae", "wireless.wpa3", "sy0-701", "wireless-security"],
  "stem": "Which WPA3 feature removes the offline-guessing weakness of the WPA2 pre-shared-key handshake?",
  "options": [
    { "id": "a", "text": "SAE (simultaneous authentication of equals)" },
    { "id": "b", "text": "TKIP", "why": "TKIP is the old WPA stream cipher and is deprecated." },
    { "id": "c", "text": "WPS push-button pairing", "why": "WPS is a convenience feature with its own weaknesses." }
  ],
  "answer": ["a"]
}
```

**Adding a tag.** Open `data/tags.json` and add a line to `tags`, in the same pull request as the questions that use it:

```json
{"id": "wireless.sae", "title": "SAE and forward secrecy", "kind": "topic"}
```

A topic id is `<area>.<topic>`, lowercase words joined by hyphens, and the area must be one of the keys of `areas` at the top
of the file (add one there if your subject is new). A pack tag is the pack's id (`my-first-pack`) with `"kind": "pack"`.
Search `data/tags.json` before adding a topic: if one already says what your question is about, use it. Tags are stable
keys, because saved progress is stored under them. To rename one, add `"renamed": {"old.id": "new.id"}` instead of editing
the id, so nobody's progress is lost.

**Where items live.** A question only your pack shows goes in `packs/<pack-id>/items/*.json`. A question more than one pack
may show goes in `bank/items/*.json`, in a file named `<pack tag>_<anything>.json` for the pack it was written for. The bank
holds only `mcq` and `multi` items without a `show` block; items that need a lab, simulated tool output or evidence
(`terminal`, `evidence`, `match`, `order`, and anything with `show`) stay in the pack that owns the lab or artifact.

### Check it

```
godot --headless --path . -s res://tools/validate_pack.gd -- res://packs/<pack-id>
```

It prints a report and exits
with an error if the pack is broken. A concept with fewer than 3 items is reported as a gap, a warning only.
With no folder given it checks every pack, the whole bank (`bank/items/`) and `data/tracks.json`.

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
