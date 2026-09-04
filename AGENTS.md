# Swift Git CLI

A thin, synchronous Swift wrapper over the `git` command-line tool — repository status, per-line diff markers, phantom removed-line data for inline diffs, blame, staging actions, branch identity, and worktree enumeration. Pure Foundation, zero dependencies, no libgit2.

- Module `GitCLI` in `Sources/GitCLI`; tests in `Tests`; `swift test` is the whole check.
- Swift 6 language mode, tools 6.0, macOS 14+, no dependencies unless the README says so.
- Part of the Sidewatch package family; every package follows the same layout and PR rules.

## Module map

- `Core/` — the engine: Git
- `Enums/` — enums with no behaviour beyond their cases and labels: GitChangeKind
- `Internal/` — non-public machinery: Git+Parsing
- `Models/` — value types — the shape of a thing, nothing else: BlameInfo, GitStatusMap, GitWorktree, HunkHeader, WorktreeSummary
- `Operations/` — the engine: operations: Git+Actions, Git+Blame, Git+Checkpoint, Git+Clone, Git+Diff, Git+Info, Git+Log, Git+MergeBase, Git+Status, Git+Worktree

## Rules

Read `CONTRIBUTING.md` before changing anything: it is the layout and PR rulebook for this package.
