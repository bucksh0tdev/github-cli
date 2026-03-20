# github-cli

> An opinionated Bash CLI for streamlined Git and GitHub workflows.

`github-cli` is a lightweight developer utility built for fast, repeatable repository operations. It wraps a focused set of Git and GitHub CLI tasks behind a small command surface: inspect a repository, create a GitHub repo from the current directory, clone a repo into a push-ready state, stage and push all changes, or intentionally reset a branch history when needed.

The project is intentionally simple in form and practical in use: one readable shell script, minimal setup, and behavior designed around everyday developer workflows.

## Highlights

- Single-file Bash implementation with no framework overhead
- Clean command interface for common Git and GitHub operations
- Native `gh` integration for repository creation and cloning
- Automatic `.gitignore` synchronization for previously tracked ignored files
- Interactive confirmation before destructive or remote-changing actions
- Push-ready clone flow that attempts to align local and remote branch state
- Small enough to audit quickly, useful enough to keep in a daily toolbelt

## Why This Exists

Many Git actions are individually simple but repetitive in practice. `github-cli` reduces that friction by providing a compact, opinionated wrapper around the commands developers run most often when starting, cloning, updating, and occasionally resetting repositories.

The goal is not to replace Git. The goal is to make a small set of high-frequency workflows faster, clearer, and safer.

## Requirements

- `bash`
- `git`
- `gh` for `create` and `clone`
- A valid `gh auth login` session for repository creation

## Installation

Clone the repository and make the script executable:

```bash
chmod +x github.sh
./github.sh help
```

For a cleaner command name, symlink it into your `PATH`:

```bash
ln -sf "$(pwd)/github.sh" ~/.local/bin/github
github help
```

If you do not create a symlink, use `./github.sh` in the examples below.

## Command Overview

| Command | Purpose | Notes |
| --- | --- | --- |
| `list` | Show repository metadata and working tree status | Requires a Git repository |
| `create` | Create a GitHub repository from the current directory | Ensures a `main` branch and an initial commit |
| `clone` | Clone a GitHub repository using `gh` | Attempts to set the clone up for immediate push usage |
| `push` | Stage, commit, and push all changes | Prompts for confirmation before pushing |
| `wipe` | Replace a branch history with a new root commit | Force-pushes after confirmation |
| `help` | Show CLI usage | Available globally and per command path |

## Quick Start

Inspect the current repository:

```bash
github list
```

Create a new private repository from the current directory:

```bash
github create "A lightweight shell utility for GitHub workflows"
```

Clone a repository and prepare it for follow-up pushes:

```bash
github clone owner/repo
```

Stage everything, create a commit, and push:

```bash
github push -m "feat: improve repository bootstrap flow"
```

Reset a branch to a fresh single-commit history:

```bash
github wipe -m "reset repository history"
```

## Detailed Usage

### `list`

Displays the current repository context and working tree state.

```bash
github list
```

What it shows:

- Repository name
- Repository path
- Current branch
- `origin` remote URL
- `git status --short` output

### `create`

Creates a GitHub repository from the current directory.

```bash
github create "My shell utility"
github create --public "My public project"
github create --private --description "Internal tooling repository"
```

Behavior:

- Initializes Git if the current directory is not already a repository
- Ensures the active branch is `main`
- Creates an initial commit if the repository has no commits yet
- Uses the directory name as the repository name
- Configures `origin` automatically when creating the remote repository
- Skips remote creation if `origin` already exists
- Does not push automatically after repository creation

### `clone`

Clones a repository through GitHub CLI and attempts to leave it in a push-ready state.

```bash
github clone owner/repo
github clone owner/repo local-directory
github clone owner/repo -u upstream
github clone owner/repo -- --depth=1
```

Behavior:

- Uses `gh repo clone`
- Supports passing clone flags through to `git clone`
- Detects the default branch under `origin`
- Checks out a usable local branch when necessary
- Configures upstream tracking when possible

### `push`

Stages all changes, creates a commit if needed, and pushes to the target branch after confirmation.

```bash
github push
github push "docs: refresh README"
github push -m "feat: add repository create flow"
github push --branch release
github push --force -m "chore: rewrite release branch"
```

Behavior:

- Requires a Git repository and an `origin` remote
- Refuses to run from a detached `HEAD`
- Applies `.gitignore` rules to already tracked ignored files
- Stages all changes with `git add -A`
- Uses `Committed By bucksh0t` as the default commit message
- Shows repository status and a staged diff summary before pushing
- Prompts for explicit confirmation before the remote update
- Supports pushing to the current branch or an alternate target branch

### `wipe`

Replaces the history of a target branch with a new orphan-based root commit and force-pushes it.

```bash
github wipe
github wipe "fresh start"
github wipe --branch develop
github wipe -m "reset repository"
```

Behavior:

- Targets `main` by default
- Creates a new orphan branch as a clean history root
- Commits the current staged project state as a single commit
- Force-pushes the result to the selected remote branch
- Uses `Wiped By bucksh0t` as the default commit message
- Prompts before performing the destructive remote update

## Design Principles

- Keep the tool small and readable
- Prefer explicit behavior over hidden automation
- Make destructive actions obvious
- Optimize for local developer productivity

## Notes

- `push` and `wipe` are interactive by design and expect terminal confirmation
- `create` and `clone` require the GitHub CLI to be installed
- The tool is intentionally opinionated around a `main`-based workflow
- The current implementation is purposefully compact and focused on shell-based developer tooling