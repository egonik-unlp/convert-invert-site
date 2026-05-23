# Git Submodules Manual

This project is intended to be a top-level integration repository that pins two
component repositories:

| Path | Purpose | Remote | Current local branch |
|---|---|---|---|
| `convert-invert/` | Rust backend and worker code | `git@github.com:egonik-unlp/convert_invert.git` | `master` |
| `convert-invert-frontend/` | React/Vite frontend | `git@github.com:egonik-unlp/convert-invert-frontend.git` | `main` |

## Current State

As of this manual, the workspace contains nested Git repositories, but it is not
yet a working submodule setup:

- The repository root has no `.gitmodules` file.
- `convert-invert/.git` and `convert-invert-frontend/.git` are full Git
  directories inside the component folders.
- The top-level `.git` directory exists, but `git status` at the root reports
  `fatal: not a git repository`.

That means the root currently behaves like an ordinary directory containing two
independent Git checkouts. A finished submodule setup should instead have:

- A valid top-level Git repository, usually called the superproject.
- A versioned `.gitmodules` file.
- One gitlink entry in the superproject index for each component path.
- Submodule Git metadata stored under the superproject's `.git/modules/`
  directory, with each submodule folder containing a small `.git` pointer file.

Until those pieces exist, commands such as `git submodule status` and
`git submodule update --init --recursive` cannot work from the project root.

## Mental Model

A Git submodule is not a copied directory. The superproject records exactly one
commit SHA for each submodule path. The submodule keeps its own history, remotes,
branches, and working tree.

This gives the integration repo reproducible component versions:

- The backend can advance independently in `convert-invert`.
- The frontend can advance independently in `convert-invert-frontend`.
- The top-level repo decides which backend commit and frontend commit belong
  together.

When a submodule changes, there are usually two commits:

1. A commit inside the component repository.
2. A commit in the superproject that updates the pinned submodule SHA.

## Finish the Submodule Setup

Only do this after deciding what the real top-level repository should be and
where it should be pushed.

If the root has no meaningful Git history yet, initialize or repair the
superproject first:

```bash
git init
```

Then register the existing nested repositories as submodules:

```bash
git submodule add --force git@github.com:egonik-unlp/convert_invert.git convert-invert
git submodule add --force git@github.com:egonik-unlp/convert-invert-frontend.git convert-invert-frontend
git submodule absorbgitdirs
```

`git submodule add` records each submodule in `.gitmodules` and stages a gitlink
for the path. `git submodule absorbgitdirs` moves embedded submodule `.git`
directories into the superproject's `.git/modules/` area, which is the normal
layout for a checked-out submodule.

Review the result:

```bash
git status
git diff --cached --submodule
git submodule status --recursive
```

Commit the superproject state:

```bash
git add .gitmodules convert-invert convert-invert-frontend docs/SUBMODULES.md README.md
git commit -m "Configure backend and frontend submodules"
```

If `git submodule add --force` refuses an existing path, use this safer fallback:

```bash
mv convert-invert ../convert-invert.backup
mv convert-invert-frontend ../convert-invert-frontend.backup
git submodule add git@github.com:egonik-unlp/convert_invert.git convert-invert
git submodule add git@github.com:egonik-unlp/convert-invert-frontend.git convert-invert-frontend
```

Then manually copy or cherry-pick any uncommitted work from the backup
directories before removing them.

## Clone This Project

For a fresh checkout after submodules are configured:

```bash
git clone --recurse-submodules <convert-invert-site-url>
cd convert-invert-site
```

If the project was cloned without submodules:

```bash
git submodule update --init --recursive
```

Use this after pulling superproject changes too. It checks out the exact
component commits pinned by the superproject.

## Check Status

From the root:

```bash
git status
git submodule status --recursive
```

Useful status prefixes from `git submodule status`:

| Prefix | Meaning |
|---|---|
| space | The submodule is initialized and checked out at the pinned commit. |
| `-` | The submodule is registered but not initialized locally. |
| `+` | The checked-out submodule commit differs from the commit pinned by the superproject. |
| `U` | The submodule has merge conflicts. |

To inspect component-level changes:

```bash
git -C convert-invert status
git -C convert-invert-frontend status
```

## Daily Development

Work inside the component repo when changing backend or frontend code:

```bash
cd convert-invert
git switch master
# edit, test, commit, push
git push origin master
```

```bash
cd convert-invert-frontend
git switch main
# edit, test, commit, push
git push origin main
```

Then update the superproject pin:

```bash
cd ..
git status
git add convert-invert convert-invert-frontend
git commit -m "Update component submodule pins"
git push
```

If only one component changed, add and commit only that path.

## Pull Updates

To update the superproject and check out the pinned component commits:

```bash
git pull --recurse-submodules
git submodule update --init --recursive
```

To ask each submodule to advance to the latest commit on its configured branch:

```bash
git submodule update --remote --merge convert-invert
git submodule update --remote --merge convert-invert-frontend
git add convert-invert convert-invert-frontend
git commit -m "Advance component submodules"
```

Use `--remote` intentionally. A normal `git submodule update --init --recursive`
does not mean "latest upstream"; it means "the exact commit recorded by the
superproject."

## Detached HEADs

After a clone or a normal submodule update, a submodule may be in detached HEAD
state. That is expected because the superproject pins a commit, not a branch.

Before editing, switch to the component branch:

```bash
git -C convert-invert switch master
git -C convert-invert-frontend switch main
```

If you already made commits while detached, create a branch before moving away:

```bash
git switch -c my-work
```

## Local Uncommitted Work

Do not update submodule pins while a component has uncommitted work unless that
is intentional:

```bash
git -C convert-invert status --short
git -C convert-invert-frontend status --short
```

Commit or stash component changes first. The superproject can record only a
submodule commit SHA; it cannot record uncommitted files inside the submodule.

## Change a Submodule URL

Edit `.gitmodules` or use:

```bash
git submodule set-url convert-invert <new-backend-url>
git submodule set-url convert-invert-frontend <new-frontend-url>
git submodule sync --recursive
git add .gitmodules
git commit -m "Update submodule remotes"
```

Use this if repository ownership changes or HTTPS URLs are preferred over SSH.

## Remove a Submodule

Removing a submodule is a superproject change:

```bash
git submodule deinit -f -- <path>
git rm -f <path>
git commit -m "Remove <path> submodule"
```

After removal, also verify that `.gitmodules` no longer contains the removed
path.

## Troubleshooting

If `git submodule status` says the current directory is not a Git repository,
the root superproject is not initialized or is broken. Fix the root repository
before debugging submodules.

If a submodule shows a leading `+`, either update it back to the pinned commit:

```bash
git submodule update --init --recursive <path>
```

or commit the new pin in the superproject:

```bash
git add <path>
git commit -m "Update <path> submodule"
```

If `.gitmodules` changed, sync local config:

```bash
git submodule sync --recursive
git submodule update --init --recursive
```

If a submodule folder contains a full `.git` directory after setup:

```bash
git submodule absorbgitdirs
```

## References

- Git `submodule` documentation: <https://git-scm.com/docs/git-submodule>
- Git `.gitmodules` documentation: <https://git-scm.com/docs/gitmodules>
