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

App bundle (needed for anything requiring TCC, e.g. audio capture — SPM stays
the primary path for logic, tests, and fast iteration):

```sh
xcodegen generate --use-cache   # prerequisite: `brew install xcodegen`.
                                # Run on fresh clone and after project.yml or file add/remove changes
xcodebuild -project AwesoMeeting.xcodeproj -scheme AwesoMeeting \
  -configuration Debug -derivedDataPath .build/xcodebuild -quiet build
# launch via LaunchServices so TCC attributes permissions to the app, not the
# terminal; --stdout/--stderr keep output attached:
open ./.build/xcodebuild/Build/Products/Debug/AwesoMeeting.app \
  --stdout "$(tty)" --stderr "$(tty)"
# capture diagnostic (per-track status once a second; exits nonzero if a
# track never flowed):
open ./.build/xcodebuild/Build/Products/Debug/AwesoMeeting.app \
  --stdout "$(tty)" --stderr "$(tty)" \
  --args --capture-check 12 --everything --out /tmp/capture-check
```

The generated `.xcodeproj` is disposable and gitignored; `project.yml` owns the
project structure. `App/Info.plist` and `App/AwesoMeeting.entitlements` are
hand-maintained committed files (edit them directly; they must live outside
`Sources/` or SPM errors on unhandled files). The signed bundle uses the
Interactive Buffoonery `DEVELOPMENT_TEAM` in project.yml — on a machine without
that cert, fetch it once with `xcodebuild ... -allowProvisioningUpdates build`
(needs the team's Apple ID signed in) or substitute your own team ID.

Design rules when touching UI (from the design system, non-negotiable): system
font for prose, monospace for data; radii ≤ 10; hairline borders; glow/shadows
vanish under reduced-transparency and increased-contrast; state is color +
shape, never color alone; no emoji.
