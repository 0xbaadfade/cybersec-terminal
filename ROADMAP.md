# Roadmap

What is built, and what is wanted. The aim is a curated bank across the whole field (see the goal in `README.md`), so most
of this page is an invitation: pick a branch, write the questions, open a pull request.

This page is generated from the packs and `data/tracks.json` when the repository is published, so the numbers are current.

## Built

| Pack | Items | Types | Difficulty 1 / 2 / 3 | Reviewed by a person | Reviewed by AI |
|---|---|---|---|---|---|
| Linux Command Line | 52 | 42 mcq, 10 terminal | 20 / 30 / 2 | 0 of 52 | 0 of 52 |
| Windows Command Line | 35 | 30 mcq, 5 terminal | 17 / 17 / 1 | 0 of 35 | 0 of 35 |
| CompTIA Security+ SY0-701 | 942 | 942 mcq | 0 / 942 / 0 | 76 of 942 | 0 of 942 |

"Reviewed by a person" is the number that matters for the *curated* bank: see `CONTENT-STANDARDS.md`. The maintainer reviews items as
they study the topic. Where the difficulty 3 column is thin, harder questions are especially welcome.

## Wanted

These branches of the skill tree (`data/tracks.json`) have no pack in this repository yet. A branch unlocks in the game once
the skill it needs is far enough along.

| Branch | Section | Needs first |
|---|---|---|
| CompTIA Network+ | Certifications | Networking Fundamentals (60%) |
| CompTIA CySA+ | Certifications | CompTIA Security+ SY0-701 (60%) |
| Malware Analysis | Skills | Binary Analysis (60%) |
| Binary Analysis | Skills | Linux Command Line (60%) |
| Binary Exploitation | Skills | Linux Command Line (60%), CompTIA Security+ SY0-701 (60%) |
| Wireless Security | Skills | CompTIA Security+ SY0-701 (60%) |
| Digital Forensics | Skills | CompTIA Security+ SY0-701 (60%), Linux Command Line (40%) |
| Networking Fundamentals | Skills | Foundations (60%) |

Not on the list? Propose it. The tree can grow: any cybersecurity skill that can be studied with questions, labs or
simulated tool output belongs here, at any level from beginner to expert.

## How to take a branch

1. Open a "Propose a pack" issue so two people do not write the same pack.
2. Copy `templates/pack/` and follow `docs/making-packs.md`. Run `validate-pack`.
3. Write the questions yourself, and label them honestly (`CONTENT-STANDARDS.md`). AI help is welcome if you say so.
4. Open a pull request. The checks run `validate-pack` on every pack.

There is no deadline and no order. Small packs are fine: a pack of fifteen good questions is a real contribution.

## Also wanted

- **Second opinions.** If an item is wrong or out of date, say so with a source: use the "Report a wrong answer" issue form.
  One reviewer needs readers who check.
- **Harder questions** (difficulty 3) in the packs that exist.
