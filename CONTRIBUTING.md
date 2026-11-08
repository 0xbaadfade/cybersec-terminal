# Contributing

Cybersec Terminal is free to use and modify (code: MIT; content: CC BY 4.0, see `LICENSE` and `packs/LICENSE.md`).
Contributions are welcome, and the easiest and most useful one is **a content pack**: questions for a certification
or skill you know well. You do not need to write code.

## Adding or improving questions

1. Read `docs/making-packs.md` and start from `templates/pack/`.
2. Run `validate-pack` on your pack and fix every error (the command is in the guide).
3. Open a pull request. The checks run `validate-pack` on every pack automatically.

Please:

- Write your own questions. Do not paste in text from exams, books, courses or other question banks that you do
  not own. By contributing you confirm the content is yours to license under CC BY 4.0.
- An `explain` is optional but worth writing: a good one says why the right answer is right and why the tempting wrong
  one is wrong, which is where the learning happens. `references` (a book, a standard, a web page) are optional too.
  The checker notes items that have no explanation.
- Label items honestly: `"source": "hand"` if you wrote it, `"source": "ai"` if an AI tool helped, and
  `"reviewed": true` only after a person has checked the facts.
- Keep to one pack, or a few related changes, per pull request.

## Code changes

Source comments sometimes cite sections of the maintainer's private design notes, which are not in this
repository; the code and the tests are the reference. A few rules the tests enforce or the
maintainers care about: `src/core/` is headless (no scene tree, no reference to `src/view/`), the view adds no game
logic, and all content stays in JSON. For anything bigger than a small fix, open an issue first so we can agree on the
approach before you build it.

Tests use the GUT framework and run headless; run the file for the area you changed
(`godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gselect=test_name.gd -gexit`).
