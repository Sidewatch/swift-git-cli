# Swift Git CLI

A thin, synchronous Swift wrapper over the `git` command-line tool — repository status, per-line diff markers, phantom removed-line data for inline diffs, blame, staging actions, branch identity, and worktree enumeration. Pure Foundation, zero dependencies, no libgit2.

## Features

- 📋 **Working-tree status** — `Git.status(repoRoot:)` returns one `(path, kind)` per changed file, parsed from `git status --porcelain=v1` (added / modified / deleted / untracked / renamed)
- 📏 **Per-line gutter markers** — `Git.lineChanges(for:repoRoot:)` maps each 1-based line to a `GitChangeKind` for editor change bars
- 👻 **Inline-diff phantom rows** — `Git.removedLines(for:repoRoot:)` returns deleted lines keyed by the surviving line they belong above, for Cursor-style inline diffs
- ➕➖ **Working-tree diff stat** — `Git.diffStat(repoRoot:)` sums total insertions/deletions vs `HEAD` (`git diff --numstat`), for a "+312 −332" badge; `WorktreeSummary` carries these per worktree
- 🧾 **Fast single-line blame** — `Git.blame(for:line:repoRoot:)` returns author, a short relative age, and the commit summary
- ✅ **Staging actions** — `stage`, `unstage`, and a destructive `discard` (revert-to-HEAD or delete-untracked)
- 🧭 **Repo discovery** — `Git.repoRoot(for:)` and repo-relative path resolution
- 🌿 **Branch identity** — `Git.currentBranch(repoRoot:)` returns the checked-out branch name, falling back to the short commit SHA on a detached `HEAD`
- 🌳 **Worktree enumeration** — `Git.worktrees(repoRoot:)` lists every `GitWorktree` (path, branch, main/linked) via `git worktree list --porcelain`, with `isCurrent(relativeTo:)` for symlink-safe "which one am I in?" checks
- 📊 **Worktree change summaries** — `Git.worktreeSummaries(repoRoot:)` pairs each worktree with a per-kind tally of its uncommitted changes (`WorktreeSummary` — `added`/`modified`/`deleted`/`untracked`/`renamed`, `changeCount`, `isDirty`, plus `insertions`/`deletions`), for a parallel-agent review rail that shows "which worktree has unreviewed work". `Git.removeWorktree(_:repoRoot:force:)` archives a finished linked worktree (`git worktree remove`; refuses a dirty tree unless forced)
- 🗺️ **Status lookup map** — `GitStatusMap.build(status:repoRoot:)` turns a status list into O(1) per-path lookups: `kind(for:)` for a file's change kind and `directoryContainsChanges(_:)` for "does this collapsed folder hold changes?", keyed under every `/private/var` ↔ `/var` alias of the repo root so lookups never miss. `GitChangeKind.letter` gives the single-letter badge (A/M/D/R/U)
- 🪶 **Zero dependencies** — Foundation only; shells out to the system `git`
- 🧪 **Fully tested** — integration tests against throwaway repos (including linked and detached worktrees) plus direct unit tests of the diff-hunk and relative-time parsers, and the status-map path keying / ancestor marking / alias resolution

## Requirements

- macOS 14+
- Swift 6.2+ (Swift 6 language mode)
- A working `git` on disk (defaults to `/usr/bin/git`; override via `Git.executable`)

> **Platform note:** this wraps the `git` binary via `Process`, so it is macOS-only (not iOS/tvOS/watchOS).

## Installation

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/Sidewatch/swift-git-cli.git", from: "1.0.0")
]
```

## Usage

```swift
import GitCLI

// Locate the repository containing a file.
guard let root = Git.repoRoot(for: someFileURL) else { return }

// What changed?
for change in Git.status(repoRoot: root) {
    print(change.kind, change.path)   // e.g. modified  Sources/App/main.swift
}

// Per-line change bars for the gutter.
let marks = Git.lineChanges(for: fileURL, repoRoot: root)   // [Int: GitChangeKind]

// Removed lines to ghost inline, keyed by the new-file line they sit above.
let removed = Git.removedLines(for: fileURL, repoRoot: root)   // [Int: [String]]

// Who last touched line 42?
if let blame = Git.blame(for: fileURL, line: 42, repoRoot: root) {
    print("\(blame.author) · \(blame.timeAgo) · \(blame.summary)")
}

// Staging actions.
Git.stage(fileURL, repoRoot: root)
Git.unstage(fileURL, repoRoot: root)
Git.discard(fileURL, kind: .modified, repoRoot: root)   // destructive

// Which branch is checked out? (short SHA when HEAD is detached)
let branch = Git.currentBranch(repoRoot: root)   // e.g. "main"

// All worktrees of the repository, main first.
for tree in Git.worktrees(repoRoot: root) {
    let marker = tree.isCurrent(relativeTo: root) ? "→" : " "
    print(marker, tree.branch ?? "(detached)", tree.path.path, tree.isMain ? "[main]" : "")
}
```

### Using a non-default git

```swift
Git.executable = "/opt/homebrew/bin/git"
```

## Notes

- All calls are **synchronous** and cheap. When scanning a whole repository, dispatch them off the main queue.
- `discard` is **destructive**: `.untracked` files are removed from disk; all other kinds are checked out from `HEAD`, discarding local edits.
- Actions like `unstage` (`git restore --staged`) require an existing `HEAD` — i.e. a repository with at least one commit. `currentBranch` likewise returns `nil` on an unborn `HEAD`.
- Escape hatch: `Git.run(_:in:)` runs any raw `git` invocation and returns its stdout (`nil` on failure).

## For agents

Read `CONTRIBUTING.md` first: the folder layout and the PR rules. `swift test` is the whole
check, and a new test must fail before the change it covers. `CLAUDE.md` / `AGENTS.md` carry a
module map.

## License

MIT
