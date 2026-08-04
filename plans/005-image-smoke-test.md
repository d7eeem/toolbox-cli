# Plan 005: Gate CI on a smoke test that proves every advertised tool runs in the image

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat d886adb..HEAD -- .github/workflows/docker-build.yml test`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: plans/004-install-ya-binary.md (soft — see note)
- **Category**: tests
- **Planned at**: commit `d886adb`, 2026-08-05

**Dependency note**: the tool list in this plan includes `ya`, which plan 004
installs. If 004 has not landed on your branch point, CI will correctly fail
on `ya` — that is the smoke test doing its job, not a defect in this plan.
Both plans are intended to be merged together.

## Why this matters

CI currently builds this image and pushes it to a public registry on every push
to `main` with **zero validation**. Nothing checks that the tools the README
advertises are actually present and runnable.

This is not hypothetical. Three separate "config references a binary that isn't
installed" defects have shipped in this repo: `glow` and `lazygit` (fixed in
plan 003) and `ya` (fixed in plan 004, and broken in the currently-published
image). Every one of them would have been caught by a five-line check that runs
the built image and looks for the binaries on `PATH`.

The download URLs are also unpinned (`releases/latest/download/...`), so an
upstream release that renames an asset or changes its archive layout will
silently produce an image missing a tool — with no signal until someone uses it.

After this lands, a build that is missing any advertised tool fails CI and is
never pushed.

## Current state

`.github/workflows/docker-build.yml` in full, exactly as it exists today:

```yaml
name: Build and Push

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}

jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write

    steps:
      - uses: actions/checkout@v7.0.1

      - name: Log in to GitHub Container Registry
        uses: docker/login-action@v4.5.2
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Build and push
        uses: docker/build-push-action@v7.3.0
        with:
          context: .
          push: ${{ github.event_name != 'pull_request' }}
          tags: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:latest
```

There is no `test/` directory in this repo. You will create one.

**Tools the image is expected to provide.** From `README.md:7-11` plus the
release-download blocks in `Dockerfile`:

- Files & disk: `ncdu`, `dua`, `eza`, `fdfind`, `file`, 7-zip, `zstd`, `pigz`, `unzip`, `unrar`
- Media: `ffmpeg`, `ffprobe`, `ffmpegthumbnailer`, `mediainfo`, `exiftool`, ImageMagick
- Text & search: `nvim`, `rg`, `batcat`, `jq`, `fzf`, `less`, `glow`
- System: `htop`, `tmux`, `curl`, `wget`, `git`, `ssh`
- Navigation: `yazi`, `ya`

Note several package names differ from their binary names — `fd-find` installs
`fdfind`, `bat` installs `batcat`, `ripgrep` installs `rg`, `neovim` installs
`nvim`, `openssh-client` installs `ssh`.

**Two binaries are genuinely ambiguous across versions** and must be checked
with alternatives rather than a single name:

- 7-zip: Ubuntu's `7zip` package has shipped `7zz`, `7za`, and `7z` depending on
  version — accept any of them.
- ImageMagick: IM6 provides `convert`, IM7 provides `magick` — accept either.

Getting these wrong would fail CI on a correct image, so the script below
supports `a|b|c` alternatives for exactly this reason.

**Repo conventions.** No application code, no linter, no existing test suite —
this will be the first test. YAML uses 2-space indentation. Commit messages are
plain lowercase imperative with no conventional-commit prefix; real examples
from `git log`:

```
fix yazi breaking changes
add Dependabot for auto-updating GitHub Actions
bump actions to latest versions (Node 24 compat)
```

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Validate workflow YAML | `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/docker-build.yml')); print('YAML OK')"` | prints `YAML OK` |
| Shell syntax check | `bash -n test/smoke.sh` | exit 0 |
| Executable bit | `test -x test/smoke.sh` | exit 0 |

Do **not** run `docker build` or `test/smoke.sh` locally — building this image
downloads the full ffmpeg and imagemagick suites and takes many minutes. The
script is validated by syntax check here; its real execution happens in CI.

## Scope

**In scope**:

- `test/smoke.sh` (create, executable)
- `.github/workflows/docker-build.yml` (modify — split build / test / push)

**Out of scope** (do NOT touch, even though they look related):

- `Dockerfile` — plan 004 owns it. Do not add or change any tool install here,
  even if you believe a tool in the list is missing. If the smoke test would
  fail, that is information for the reviewer, not a reason to edit the image.
- `README.md`, `compose.yaml`, `config/yazi/**`, `plans/**`.
- Adding SHA-based image tags or version pinning — a separate plan covers those.
  This plan changes **only** whether a build is validated before being pushed.

## Git workflow

- Branch: `advisor/005-image-smoke-test`
- One commit; message style is lowercase imperative with no prefix, e.g.
  `add image smoke test and gate push on it`
- Do NOT push or open a PR.

## Steps

### Step 1: Create `test/smoke.sh`

Create the directory `test/` and the file `test/smoke.sh` with exactly this
content:

```bash
#!/usr/bin/env bash
# Smoke test: assert every tool advertised in README.md is present and runnable
# in the built image. Usage: ./test/smoke.sh [image-tag]
#
# Entries may list alternatives separated by "|" — any one satisfies the check.
# This exists because a few package/binary names differ across upstream
# versions (7-zip ships 7zz/7za/7z; ImageMagick 6 ships convert, 7 ships magick).
set -eu

IMAGE="${1:-ghcr.io/d7eeem/toolbox-cli:latest}"

TOOLS="ncdu dua eza fdfind file 7zz|7z|7za zstd pigz unzip unrar
ffmpeg ffprobe ffmpegthumbnailer mediainfo exiftool convert|magick
nvim rg batcat jq fzf less glow
htop tmux curl wget git ssh
yazi ya"

echo "Smoke testing image: $IMAGE"

docker run --rm -i "$IMAGE" bash -s -- $TOOLS <<'SCRIPT'
set -u
failed=0
for entry in "$@"; do
  found=""
  # Split on "|" and accept the first alternative that resolves.
  IFS='|'
  for name in $entry; do
    if command -v "$name" >/dev/null 2>&1; then
      found="$name"
      break
    fi
  done
  unset IFS

  if [ -z "$found" ]; then
    echo "FAIL $entry (none of these are on PATH)"
    failed=$((failed + 1))
    continue
  fi

  # Best-effort execution probe. Many of these do not support --version
  # (less uses -V; unrar and 7-zip print a banner and may exit non-zero),
  # so a non-zero exit here is not treated as a failure. The binding
  # constraint is presence on PATH.
  "$found" --version >/dev/null 2>&1 || "$found" -V >/dev/null 2>&1 || true
  echo "ok   $found"
done

if [ "$failed" -gt 0 ]; then
  echo "---"
  echo "$failed tool(s) missing"
  exit 1
fi
echo "---"
echo "all tools present"
SCRIPT
```

Then make it executable: `chmod +x test/smoke.sh`

**Verify syntax**: `bash -n test/smoke.sh && echo SMOKE_SYNTAX_OK`
→ prints `SMOKE_SYNTAX_OK`

**Verify executable**: `test -x test/smoke.sh && echo SMOKE_EXEC_OK`
→ prints `SMOKE_EXEC_OK`

**Verify the alternatives-splitting logic works** — run just the inner loop
logic against your own machine, where `bash`, `ls`, and a deliberately absent
name exercise all three paths:

```bash
bash -c '
set -u
failed=0
for entry in "bash" "definitelynotreal|ls" "nope1|nope2"; do
  found=""
  IFS="|"
  for name in $entry; do
    if command -v "$name" >/dev/null 2>&1; then found="$name"; break; fi
  done
  unset IFS
  if [ -z "$found" ]; then echo "FAIL $entry"; failed=$((failed+1)); continue; fi
  echo "ok   $found"
done
echo "failed=$failed"'
```

→ must print `ok   bash`, `ok   ls`, `FAIL nope1|nope2`, and `failed=1`.
This confirms alternatives resolve, fall through in order, and that a fully
missing entry is counted.

### Step 2: Split the workflow into build → smoke test → push

Replace the single `Build and push` step in
`.github/workflows/docker-build.yml` with the three steps below. Everything
above it (name, triggers, env, permissions, checkout, registry login) stays
exactly as it is.

```yaml
      - name: Build
        uses: docker/build-push-action@v7.3.0
        with:
          context: .
          load: true
          push: false
          tags: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:latest
          cache-from: type=gha
          cache-to: type=gha,mode=max

      - name: Smoke test
        run: ./test/smoke.sh ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:latest

      - name: Push
        if: ${{ github.event_name != 'pull_request' }}
        uses: docker/build-push-action@v7.3.0
        with:
          context: .
          push: true
          tags: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:latest
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

Why it is shaped this way — do not collapse these back into one step:

- `load: true, push: false` puts the built image into the runner's local Docker
  daemon so the smoke test can actually `docker run` it.
- The smoke test runs **between** build and push, so a broken image is never
  published. This is the entire point of the plan.
- The `Push` step keeps the existing `if:` guard so pull requests build and are
  tested but never push — matching current behavior.
- `cache-from`/`cache-to: type=gha` is required here, not optional: without it
  the second `build-push-action` invocation would rebuild the whole image from
  scratch and roughly double CI time. With it, the push step reuses the layers
  the build step just produced.

**Verify YAML parses and the steps are in the right order**:

```bash
python3 -c "
import yaml
d=yaml.safe_load(open('.github/workflows/docker-build.yml'))
steps=d['jobs']['build']['steps']
names=[s.get('name') for s in steps]
assert 'Build' in names and 'Smoke test' in names and 'Push' in names, names
assert names.index('Build') < names.index('Smoke test') < names.index('Push'), names
b=steps[names.index('Build')]['with']
assert b['load'] is True and b['push'] is False, b
p=steps[names.index('Push')]
assert p['with']['push'] is True
assert 'pull_request' in p['if']
assert 'build-args' not in b and 'build-args' not in p['with'], 'build-args must not return'
print('WORKFLOW OK')"
```

→ prints `WORKFLOW OK`

**Verify the token is still used only for login**:
`grep -c 'secrets.GITHUB_TOKEN' .github/workflows/docker-build.yml` → prints `1`

## Test plan

This plan *is* the test infrastructure — it adds the repo's first test. There is
no existing test to model after.

What `test/smoke.sh` covers:

- **Happy path**: every advertised binary resolves on `PATH` in the built image.
- **The specific regression class this repo has hit three times**: a tool
  referenced by config or README that was never installed (`glow`, `lazygit`,
  `ya`).
- **Named edge cases**: binaries whose upstream name varies (7-zip, ImageMagick)
  are handled via alternatives so a correct image cannot fail on naming; tools
  that do not support `--version` are probed with `-V` and then ignored, so the
  check is presence-based rather than flag-based.

What it deliberately does not cover: that each tool *works correctly*, only that
it exists and is executable. That is the right scope for a build gate.

Verification in this plan is the syntax check plus the Step 1 logic harness,
which exercises the alternatives code path on the local machine without needing
the image. The script's true first run is in CI.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `test -x test/smoke.sh` exits 0
- [ ] `bash -n test/smoke.sh` exits 0
- [ ] The Step 1 logic harness prints `ok   bash`, `ok   ls`,
      `FAIL nope1|nope2`, `failed=1`
- [ ] `grep -c 'ya' test/smoke.sh` is at least 1 (the `ya` binary is listed)
- [ ] The workflow YAML parses and asserts pass: `Build` before `Smoke test`
      before `Push`; build has `load: true`/`push: false`; push has `push: true`
      and a `pull_request` guard; no `build-args` in either
- [ ] `grep -c 'secrets.GITHUB_TOKEN' .github/workflows/docker-build.yml` prints `1`
- [ ] `git status --porcelain` shows changes only to
      `.github/workflows/docker-build.yml` and the new `test/smoke.sh`

## STOP conditions

Stop and report back (do not improvise) if:

- `.github/workflows/docker-build.yml` does not match the "Current state"
  excerpt.
- A `test/` directory already exists with different contents — do not overwrite;
  report what is there.
- The Step 1 logic harness does not produce exactly the expected four lines.
  Report the actual output; do not adjust the assertion to match.
- You believe a tool in the `TOOLS` list is not actually installed by the
  `Dockerfile`. **Do not edit the `Dockerfile` to add it and do not silently
  remove it from the list** — report which tool and why, and stop. Whether the
  image or the list is wrong is a judgment call for the reviewer.

## Maintenance notes

For whoever owns this next:

- **The `TOOLS` list must be kept in sync with `README.md`.** If a tool is added
  to the image and advertised, add it here too, or the gate silently stops
  covering it.
- **Alternatives syntax (`a|b`) is the escape hatch for upstream renames.** When
  a build starts failing on a tool that is clearly installed, the likely cause is
  a renamed binary — add the new name as an alternative rather than deleting the
  entry.
- **CI now builds twice per push** (once to load and test, once to push), made
  cheap by the GHA layer cache. If cache behavior ever regresses, the symptom is
  CI time roughly doubling; the fix is to check `cache-from`/`cache-to` are still
  present on both steps, not to remove the smoke test.
- **A reviewer should scrutinize** that the smoke test sits strictly between
  build and push — if it ever moves after the push, a broken image reaches the
  registry before anyone finds out, which is the exact failure this plan exists
  to prevent.
- **Deliberately deferred**: asserting tool *versions*, and adding immutable
  SHA image tags. Both belong with the version-pinning work, not here.
