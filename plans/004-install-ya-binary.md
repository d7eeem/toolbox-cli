# Plan 004: Install the `ya` binary so yazi's archive extraction works

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat d886adb..HEAD -- Dockerfile`
> If `Dockerfile` changed since this plan was written, compare the "Current
> state" excerpt against the live code before proceeding; on a mismatch, treat
> it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: bug
- **Planned at**: commit `d886adb`, 2026-08-05

## Why this matters

yazi ships **two** binaries in its release archive: `yazi` (the file manager)
and `ya` (its companion CLI, used for plugin management and for the `ya pub`
IPC commands). The Dockerfile moves only `yazi` onto the `PATH` and then deletes
the extraction directory, so `ya` never makes it into the image.

This breaks a feature that the baked-in config actively uses. `config/yazi/yazi.toml:47`
defines the archive-extraction opener as `ya pub extract --list "$@"`, which is
wired to every zip, tar, 7z, xz, bzip and rar file by the `[open]` rules. In the
published image, selecting an archive and pressing Enter silently does nothing —
`ya` is not found.

After this change, extraction works and `ya` is available for plugin management
inside the container.

## Current state

Only one file is involved: `Dockerfile`.

`Dockerfile:52-57`, exactly as it exists today:

```dockerfile
# yazi
RUN curl -Lo /tmp/yazi.zip \
        https://github.com/sxyazi/yazi/releases/latest/download/yazi-x86_64-unknown-linux-musl.zip \
    && unzip /tmp/yazi.zip -d /tmp/yazi \
    && mv /tmp/yazi/yazi*/yazi /usr/local/bin/ \
    && rm -rf /tmp/yazi*
```

Line 56 moves `yazi` only. Line 57 then deletes `/tmp/yazi*`, taking `ya` with it.

**Verified evidence.** The release archive was downloaded and listed while
writing this plan. Its full contents:

```
     7243  yazi-x86_64-unknown-linux-musl/README.md
 24719760  yazi-x86_64-unknown-linux-musl/yazi
     1065  yazi-x86_64-unknown-linux-musl/LICENSE
  1823728  yazi-x86_64-unknown-linux-musl/ya
```

Both binaries are present, in a directory matching the `yazi*` glob already used
on line 56. yazi's official installation docs say to "add `yazi` and `ya` to your
`$PATH`".

The consumer, `config/yazi/yazi.toml:47`, as it exists today:

```toml
  { run = 'ya pub extract --list "$@"', desc = "Extract here", for = "unix" },
```

**Repo conventions.** No application code, no linter, no test suite. The
Dockerfile installs four tools from GitHub releases (eza, dua, yazi, glow), each
as a single `RUN` with `&&`-chained steps, 4-space continuation indent, and a
`rm -rf /tmp/<name>*` cleanup last. Commit messages are plain lowercase
imperative with no conventional-commit prefix; real examples from `git log`:

```
fix yazi breaking changes
remove GitHub API calls from build, use direct /latest/download/ URLs instead
bump actions to latest versions (Node 24 compat)
```

**Critical shell constraint.** Docker `RUN` uses `/bin/sh`, which on Ubuntu is
`dash`. **dash does not support brace expansion**, so `mv .../{yazi,ya} ...`
would fail at build time. Both source paths must be written out in full.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Grep audit | `grep -n 'yazi\*' Dockerfile` | shows the mv line |
| Shell-syntax sanity | `dash -n <(...)` — see Step 1 | exit 0 |

This repo has no build, test, lint, or typecheck command. Do **not** run
`docker build` — this image installs the full ffmpeg and imagemagick suites and
takes many minutes.

## Scope

**In scope** (the only file you may modify):

- `Dockerfile` — line 56 only

**Out of scope** (do NOT touch, even though they look related):

- `config/yazi/yazi.toml` — the `ya pub extract` opener on line 47 is **correct
  and stays**. It is the thing this plan makes work. Do not "fix" it to call
  something else.
- The `eza`, `dua`, and `glow` install blocks in `Dockerfile`.
- The `curl`, `unzip`, and `rm -rf` lines of the yazi block — only the `mv`
  changes.
- `README.md` — the tool list mentions "yazi (terminal file manager)", which
  remains accurate. `ya` is a companion binary, not a separately advertised
  tool. No README change.
- `.github/workflows/**`, `compose.yaml`, `plans/**`.

## Git workflow

- Branch: `advisor/004-install-ya-binary`
- One commit; message style is lowercase imperative with no prefix, e.g.
  `install ya alongside yazi so archive extraction works`
- Do NOT push or open a PR.

## Steps

### Step 1: Move both binaries out of the archive

In `Dockerfile`, change line 56 from:

```dockerfile
    && mv /tmp/yazi/yazi*/yazi /usr/local/bin/ \
```

to:

```dockerfile
    && mv /tmp/yazi/yazi*/yazi /tmp/yazi/yazi*/ya /usr/local/bin/ \
```

Both source paths are written out in full. **Do not** use `{yazi,ya}` brace
expansion — Docker `RUN` uses dash, which does not support it, and the build
would fail.

Leave every other line of the block unchanged.

**Verify the edit is present**: `grep -c 'yazi\*/yazi /tmp/yazi/yazi\*/ya' Dockerfile`
→ prints `1`

**Verify no brace expansion crept in**: `grep -c '{yazi,ya}' Dockerfile`
→ returns 0 matches (exit 1)

**Verify the RUN block is valid dash syntax** — extract the block and parse it
with dash, substituting a no-op for the network commands:

```bash
sed -n '/^# yazi$/,/rm -rf \/tmp\/yazi\*/p' Dockerfile \
  | sed '1d; s/^RUN //' \
  | dash -n /dev/stdin && echo "DASH SYNTAX OK"
```

→ prints `DASH SYNTAX OK`

If `dash` is not installed on this machine, run the same check with
`sh -n` instead and note in your report which shell you used.

### Step 2: Confirm the block is otherwise intact

**Verify**: `sed -n '/^# yazi$/,/rm -rf \/tmp\/yazi\*/p' Dockerfile`

→ must print exactly:

```dockerfile
# yazi
RUN curl -Lo /tmp/yazi.zip \
        https://github.com/sxyazi/yazi/releases/latest/download/yazi-x86_64-unknown-linux-musl.zip \
    && unzip /tmp/yazi.zip -d /tmp/yazi \
    && mv /tmp/yazi/yazi*/yazi /tmp/yazi/yazi*/ya /usr/local/bin/ \
    && rm -rf /tmp/yazi*
```

Compare character by character. Only the `mv` line differs from the original.

## Test plan

This repo has no test suite. A CI smoke test that would assert `ya` is on the
image's `PATH` is a separate plan (005) — if that plan has already landed on
your branch point, its `test/smoke.sh` already lists `ya` and will cover this
permanently.

Verification for this plan is:

1. **Structural** — Step 2 pins the exact resulting block, so a stray edit to
   any other line fails the check.
2. **Shell-correctness** — Step 1's `dash -n` parse is the substantive check.
   It is what catches the brace-expansion trap, which is the only realistic way
   to get this wrong.

Do **not** add a test framework, a `package.json`, or a new CI job.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `grep -c 'yazi\*/yazi /tmp/yazi/yazi\*/ya' Dockerfile` prints `1`
- [ ] `grep -c '{yazi,ya}' Dockerfile` returns 0 matches
- [ ] The `dash -n` (or `sh -n`) parse of the yazi RUN block exits 0
- [ ] `sed -n '/^# yazi$/,/rm -rf \/tmp\/yazi\*/p' Dockerfile` matches the
      six-line block in Step 2 exactly
- [ ] `grep -c 'ya pub extract' config/yazi/yazi.toml` still prints `1`
      (the consumer was not touched)
- [ ] `git status --porcelain` shows a change only to `Dockerfile`

## STOP conditions

Stop and report back (do not improvise) if:

- The yazi block in `Dockerfile` does not match the "Current state" excerpt.
- The `dash -n` parse fails — report the exact error rather than rewriting the
  line a different way.
- You conclude `config/yazi/yazi.toml` also needs changing. It does not; the
  whole point is that its `ya pub extract` opener becomes functional.
- You find that `ya` is already being installed somewhere else in the
  `Dockerfile` (it is not, as of `d886adb`) — if so, stop, because the fix would
  be a duplicate.

## Maintenance notes

For whoever owns this next:

- **`ya` and `yazi` are versioned together** and must come from the same
  archive. If the yazi install block is ever changed to pin a version, both
  binaries must still be taken from that same pinned archive — a mismatched
  `ya` can fail against a different `yazi` IPC protocol.
- **This class of bug — config referencing an uninstalled binary — has now
  happened three times** in this repo (glow, lazygit, and `ya`). The durable fix
  is the CI smoke test in plan 005, which asserts every expected binary is on
  `PATH` in the built image. That plan is the real regression guard; this one is
  the point fix.
- **A reviewer should scrutinize** that the `mv` uses two full paths rather than
  brace expansion, since the brace form looks cleaner and would pass a casual
  read while failing the actual build under dash.
