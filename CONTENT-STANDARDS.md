# Content standards

Cybersec Terminal is a free, curated bank of cybersecurity knowledge for practitioners at every level, from a first Linux
command to expert work. It began as the maintainer's own study bank: new items are added as they research and learn a
topic. Anyone is welcome to add their own to benefit the community. This page says what a good item is, how items are
labelled, and what "curated" means here, so a reader can tell how far to trust a question.

## Who it is for

Any cybersecurity practitioner: someone starting out, someone preparing for a certification, someone changing
specialism, someone already senior who wants to keep a skill sharp. A pack should eventually cover its skill from
beginner to expert. `difficulty` is a guide to that (1, 2 or 3):

| Difficulty | A person who can answer it |
|---|---|
| 1 | has learned the basics and can recall or recognise them |
| 2 | has used the skill and can apply it to a normal situation |
| 3 | has real experience and can choose between close options, or spot a subtle flaw |

## The review label

What matters about an item is whether it has been checked, and by whom, not how it was drafted. An item may carry one
optional field, `reviewed_by`:

- **`"human"`**: the maintainer has checked it as described below. Only these items are the *curated* bank.
- **`"ai"`**: an AI tool has checked it against a cited source, using the same list. A useful extra look, but it is not the
  curated bank, and a person can still find what it missed.
- **left out**: nobody has reviewed it yet.

Only the maintainer sets `reviewed_by`. Contributors leave it out.

## AI help

AI help is welcome for drafting questions, and plenty of good items will start that way. It is also a way to produce
confident, wrong answers, so the rule is about checking, not about banning: an item counts as reviewed only when it has
been checked against a source. Do not paste in anything an AI produced from a book, exam or course you do not own (see
"Sources and licensing").

## What "reviewed" means

The maintainer does the human reviewing. An item gets `reviewed_by: human` only when the maintainer has done all of this:

1. Checked that the marked answer is correct and that every wrong option is actually wrong, against an authoritative
   source: a standard, vendor documentation, an RFC, a manual page, or a recognised textbook. Memory alone is not a check.
2. Checked that the explanation is true and says why, not only what.
3. Checked that nothing is copied from a source the contributor does not own.
4. Checked that the difficulty is reasonable and the question has one defensible answer (or, for `multi`, exactly the
   stated number).

The source goes in the item's `references`, so anyone can verify the check for themselves. That is the safeguard: the
maintainer reviews their own items as well as contributed ones, and a reviewed item always shows what it was checked against.
Contributors leave `reviewed_by` out and the maintainer sets it after checking. Readers who disagree are encouraged to
say so: see "Corrections".

**If a reviewed item is changed** (a fix, a rewording, a new answer), `reviewed_by` is removed until someone
checks it again.

## What a good item looks like

- **One idea per question.** The stem is clear without the options and has no trick wording.
- **Plausible wrong options.** Each wrong option is something a learner might really believe. Fill in `why` for them:
  that is where the learning happens.
- **An `explain`** that says why the right answer is right and why the tempting wrong one is wrong.
- **`references`** (a book, a standard, a web page) wherever a fact could be disputed or will change.
- **Up to date.** If an answer depends on a version or a date, say which in the stem.
- **Tagged for what it teaches.** `tags` give the item one to three topics (`wireless.sae`) and the pack or packs it is for,
  so the spaced-repetition scheduler and the skill tree can use it and a question on a shared subject is written once, not
  once per pack. Pick the topic that names the one idea the question tests; do not add a topic to widen its reach.

`docs/making-packs.md` has the file format and the rules for tags, and `validate-pack` checks them.

## Sources and licensing

The packs are licensed CC BY 4.0 (`packs/LICENSE.md`). By contributing you say the content is yours to license that way.

- Write in your own words. Do **not** copy questions, explanations or answer keys from exams, exam dumps, practice-test
  books, video courses or other question banks, even if you own a copy: owning a licence to use a book is not a licence to
  republish it. Questions that can only be rebuilt from such a source do not belong here.
- Facts and public standards are free to use; their wording is not always. Paraphrase, and cite.
- Keep it safe to publish. Labs and tool output are simulated. Do not include working exploit code for live systems,
  real credentials, real people's data, or real targets.
- Certification and vendor names are used only to say what a pack helps you study for. The project is independent and is
  not approved by any certification body.

## Corrections

A wrong or outdated answer is a real defect. Use the "Report a wrong answer" issue form, or open a pull request with the
fix. Say what is wrong and give a source. Corrections are welcome from anyone, and they are also the second pair of eyes
that a single reviewer needs.

## What is promised, and what is not

- Items are labelled by whether, and by whom, they have been reviewed. The counts per pack are in
  `ROADMAP.md`, and `validate-pack` prints them.
- When the game builds a round it serves human-reviewed items first, then AI-reviewed ones, then the rest.
- No item is guaranteed correct. Reviewed means the maintainer checked it against the cited source, not that it is beyond
  doubt. For an exam, always check the exam's own current objectives.
