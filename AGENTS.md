# Working on awesoMeeting

## Where the docs live

- **This repo (public):** code, tests, and the public README. Nothing else.
- **[awesoMeeting-private](https://github.com/Interactive-Buffoonery/awesoMeeting-private)** (local: `~/personal-dev/awesoMeeting-private`): the product
  spec (`notes/awesoMeeting.md` — read it before backend decisions; it wins on
  conflict), research notes, and the design-system export
  (`claude-design-system/` — tokens, components, and the design rules in its
  `SKILL.md`/`readme.md`). Internal reasoning, competitive notes, and specs stay
  there — never in this repo.

## Commits, PRs, and AI attribution

- Work on a branch and open a PR into `main`; don't push to `main` directly.
- **No AI credit trailers in commits** — no `Co-Authored-By: Claude`, no
  "Generated with Claude Code" footers.
- Instead, acknowledge AI assistance once per PR, in the PR description, with
  the human reviewer named:

  ```
  Assisted-by: AI (Claude Code)
  Reviewed-by: @serabi
  ```

  The meaning: the code was written with AI help, and a human read and approved
  every line before merge.
- Show the exact staged file list and the draft commit message before
  committing or pushing anything.

## Basics

```sh
swift build && swift test              # must be green before any PR
swift run                              # launch the app
swift run AwesoMeeting --snapshot <dir>  # Mocha+Latte PNGs for UI review
```

Design rules when touching UI (from the design system, non-negotiable): system
font for prose, monospace for data; radii ≤ 10; hairline borders; glow/shadows
vanish under reduced-transparency and increased-contrast; state is color +
shape, never color alone; no emoji.
