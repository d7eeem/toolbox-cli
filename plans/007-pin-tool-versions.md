# Plan 007: Pin tool versions and publish immutable SHA image tags

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat d886adb..HEAD -- Dockerfile .github/workflows/docker-build.yml .github/dependabot.yml README.md`
> On a mismatch with the "Current state" excerpts, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: MED
- **Depends on**: plans/005-image-smoke-test.md (**hard** — see below)
- **Category**: tech-debt
- **Planned at**: commit `d886adb`, 2026-08-05
- **NOT YET EXECUTED** — written for later execution, deliberately held back
  because it changes build behavior.

**Hard dependency**: plan 005 adds a CI smoke test that proves the built image
still contains every tool. Pinning versions means a wrong or withdrawn version
tag produces a broken image. Without 005's gate, that breakage reaches the
registry silently. Do not execute this plan until 005 is merged.

## Why this matters

Every external tool in this image is fetched from a moving target. `eza`, `yazi`,
and `glow` use `releases/latest/download/...`; `dua` resolves "latest" through a
redirect at build time; LazyVim is `git clone`d from `main` with no ref. Two
builds of the same commit, a month apart, produce different images. There is no
way to reproduce a known-good build, and no way to roll back a deployment —
because CI publishes only `:latest`, which is overwritten every push.

For an appliance you leave running, that is the wrong trade. You want the image
to change when *you* decide it changes.

There is a real cost: pinned versions go stale unless someone bumps them.
Dependabot's `docker` ecosystem tracks `FROM` lines, **not** GitHub-release
version `ARG`s, so those bumps stay manual. That is the trade-off being accepted.

Note this partially reverses plan 002. That plan replaced an authenticated
GitHub API call with a redirect-based "resolve latest" trick to remove a token
leak. The token removal stands; the *dynamic resolution* becomes a manual bump
helper rather than the build mechanism.

## Current state

`Dockerfile:1-2` today:

```dockerfile
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
```

The four release-download blocks today (`Dockerfile:34-68`) — abridged to the
lines that matter:

```dockerfile
# eza
RUN wget -qO /tmp/eza.tar.gz \
        "https://github.com/eza-community/eza/releases/latest/download/eza_x86_64-unknown-linux-musl.tar.gz" \

# dua-cli — version resolved from the release redirect; needs no auth
RUN DUA_VERSION=$(curl -sILo /dev/null -w '%{url_effective}' \
        https://github.com/Byron/dua-cli/releases/latest \
        | sed 's#.*/tag/v##') \
    && [ -n "$DUA_VERSION" ] \
    && wget -qO /tmp/dua.tar.gz \
        "https://github.com/Byron/dua-cli/releases/latest/download/dua-v${DUA_VERSION}-x86_64-unknown-linux-musl.tar.gz" \

# yazi
RUN curl -Lo /tmp/yazi.zip \
        https://github.com/sxyazi/yazi/releases/latest/download/yazi-x86_64-unknown-linux-musl.zip \

# glow — markdown renderer used by yazi's glow previewer
RUN GLOW_VERSION=$(curl -sILo /dev/null -w '%{url_effective}' \
        https://github.com/charmbracelet/glow/releases/latest \
        | sed 's#.*/tag/v##') \
```

`Dockerfile:68` (LazyVim), today — unpinned, and it bakes the full `.git`
history into the image:

```dockerfile
RUN git clone https://github.com/LazyVim/starter ~/.config/nvim
```

`.github/dependabot.yml` in full today:

```yaml
version: 2
updates:
  - package-ecosystem: github-actions
    directory: /
    schedule:
      interval: weekly
```

**Asset naming differs per tool** — verified against live GitHub while writing
this plan. Get these wrong and the build 404s:

| Tool | Asset name pattern | Version in name? |
|---|---|---|
| eza | `eza_x86_64-unknown-linux-musl.tar.gz` | no |
| dua | `dua-v${V}-x86_64-unknown-linux-musl.tar.gz` | yes, **with** `v` |
| yazi | `yazi-x86_64-unknown-linux-musl.zip` | no |
| glow | `glow_${V}_Linux_x86_64.tar.gz` | yes, **without** `v` |

Pinned downloads use `releases/download/<tag>/<asset>` rather than
`releases/latest/download/<asset>`.

**Repo conventions.** Single `RUN` per tool, `&&`-chained, 4-space continuation
indent, `rm -rf /tmp/<name>*` last. Commit messages plain lowercase imperative,
no prefix.

## Commands you will need

| Purpose | Command | Expected |
|---|---|---|
| Validate workflow YAML | `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/docker-build.yml')); print('OK')"` | prints `OK` |
| Validate dependabot YAML | `python3 -c "import yaml; yaml.safe_load(open('.github/dependabot.yml')); print('OK')"` | prints `OK` |
| Asset URL probe | `curl -sIo /dev/null -w '%{http_code}' -L "<url>"` | `200` |

Do **not** run `docker build`.

## Scope

**In scope**: `Dockerfile`, `.github/workflows/docker-build.yml`,
`.github/dependabot.yml`, `README.md` (one new section).

**Out of scope**:
- The `USER`/non-root work — separate plan.
- Removing the redirect-resolution logic entirely; it is repurposed, not deleted
  (see Step 5).
- `compose.yaml` — consuming SHA tags via `TOOLBOX_TAG` is a deployment concern
  handled with the hardening plan.
- `config/yazi/**`, `test/**`.

## Git workflow

- Branch: `advisor/007-pin-tool-versions`
- Commit per step is fine; lowercase imperative messages, no prefix.
- Do NOT push or open a PR.

## Steps

### Step 1: Resolve the current versions and record them

Run, and write down each result:

```bash
for r in eza-community/eza Byron/dua-cli sxyazi/yazi charmbracelet/glow; do
  printf '%s -> %s\n' "$r" \
    "$(curl -sILo /dev/null -w '%{url_effective}' https://github.com/$r/releases/latest | sed 's#.*/tag/##')"
done
git ls-remote https://github.com/LazyVim/starter HEAD
```

**Verify**: four lines each ending in a tag like `v0.23.5`, plus a 40-character
LazyVim commit SHA.

### Step 2: Add version ARGs

Insert after `Dockerfile:2`, substituting the values from Step 1:

```dockerfile
ARG EZA_VERSION=v0.0.0
ARG DUA_VERSION=v0.0.0
ARG YAZI_VERSION=v0.0.0
ARG GLOW_VERSION=v0.0.0
ARG LAZYVIM_REF=0000000000000000000000000000000000000000
```

**Verify**: `grep -c '^ARG .*_VERSION=v' Dockerfile` prints `4`; `grep -c '^ARG LAZYVIM_REF=' Dockerfile` prints `1`.

### Step 3: Switch each download to the pinned URL

Replace `releases/latest/download/<asset>` with
`releases/download/${<TOOL>_VERSION}/<asset>` in all four blocks, keeping each
tool's asset-name pattern from the table above. For `dua`, the asset embeds the
tag **with** its `v`; for `glow`, **without** — strip it with
`${GLOW_VERSION#v}`.

Delete the now-unused `DUA_VERSION=$(curl ...)` and `GLOW_VERSION=$(curl ...)`
resolution lines and their `[ -n "$..." ]` guards — the ARG supplies the value.

**Verify no dynamic resolution remains**: `grep -c 'releases/latest' Dockerfile` returns 0 matches.

**Verify each pinned URL actually resolves** — for each of the four, using your
Step 1 values:

```bash
curl -sIo /dev/null -w '%{http_code}\n' -L "https://github.com/<repo>/releases/download/<tag>/<asset>"
```

→ each prints `200`. **Any 404 is a STOP condition** — it means the asset
pattern is wrong for that version.

### Step 4: Pin LazyVim and drop its git history

Replace `Dockerfile:68` with:

```dockerfile
RUN git clone https://github.com/LazyVim/starter ~/.config/nvim \
    && git -C ~/.config/nvim checkout ${LAZYVIM_REF} \
    && rm -rf ~/.config/nvim/.git
```

**Verify**: `grep -c 'LAZYVIM_REF' Dockerfile` prints `1`; `grep -c 'rm -rf ~/.config/nvim/.git' Dockerfile` prints `1`.

### Step 5: Keep a bump helper

Add above the ARG block:

```dockerfile
# Tool versions are pinned so a given commit always builds the same image.
# To bump, run scripts/latest-versions.sh and update the values below.
```

Create `scripts/latest-versions.sh` containing the Step 1 command, `chmod +x` it.

**Verify**: `bash -n scripts/latest-versions.sh && test -x scripts/latest-versions.sh && echo OK` prints `OK`.

### Step 6: Publish an immutable SHA tag

In the workflow, add a SHA tag alongside `:latest` on **both** the Build and
Push steps (they must match, or the push step rebuilds):

```yaml
          tags: |
            ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:latest
            ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }}
```

**Verify**: YAML parses and both steps' `tags` contain `github.sha`.

### Step 7: Watch the base image with dependabot

Append to `.github/dependabot.yml`:

```yaml
  - package-ecosystem: docker
    directory: /
    schedule:
      interval: weekly
```

**Verify**: `python3 -c "import yaml; d=yaml.safe_load(open('.github/dependabot.yml')); e=[u['package-ecosystem'] for u in d['updates']]; assert set(e)=={'github-actions','docker'}, e; print('OK')"` prints `OK`.

### Step 8: Document it

Add a `## Image tags and rollback` section to `README.md` explaining that every
build publishes `:latest` and an immutable `:<commit-sha>`, that rolling back
means pointing at a SHA tag and re-pulling, and that tool versions are pinned
via `ARG`s bumped with `scripts/latest-versions.sh`.

**Verify**: `grep -c 'Image tags and rollback' README.md` prints `1`.

## Test plan

The substantive test is plan 005's CI smoke test — with versions pinned, it is
what proves a pinned tag still yields an image containing every tool. That is
precisely why 005 is a hard dependency.

Plan-local verification: Step 3's four HTTP probes are the real gate, since a
wrong asset pattern is the dominant failure mode and produces a 404 rather than
anything subtle.

Do not add a test framework or a new CI job beyond the tag change.

## Done criteria

- [ ] `grep -c 'releases/latest' Dockerfile` returns 0 matches
- [ ] Four `ARG *_VERSION` and one `ARG LAZYVIM_REF` present, none left at the `v0.0.0` / all-zeros placeholder
- [ ] All four pinned asset URLs return HTTP `200`
- [ ] `grep -c 'rm -rf ~/.config/nvim/.git' Dockerfile` prints `1`
- [ ] `test -x scripts/latest-versions.sh` exits 0
- [ ] Workflow YAML parses; Build and Push steps carry identical `tags` including `github.sha`
- [ ] dependabot lists exactly `github-actions` and `docker`
- [ ] `grep -c 'Image tags and rollback' README.md` prints `1`
- [ ] `git status --porcelain` shows only the in-scope paths plus `scripts/latest-versions.sh`

## STOP conditions

- Any pinned asset URL returns anything but `200`.
- A "Current state" excerpt does not match the live file.
- `git ls-remote` for LazyVim returns no SHA.
- The Build and Push `tags` blocks end up differing — that silently causes a full
  rebuild on push and must be fixed, not tolerated.
- Plan 005 is not merged at your branch point. Stop: without the smoke test this
  change can publish a broken image undetected.

## Maintenance notes

- **Pins go stale silently.** Dependabot watches `FROM` and actions, not release
  `ARG`s. Run `scripts/latest-versions.sh` periodically; treat a bump as a normal
  PR that CI smoke-tests.
- **Rollback path**: point at `:<sha>` and re-pull. Do not delete old SHA tags
  from the registry or that path disappears.
- **A reviewer should scrutinize** the four asset-name patterns — they are
  inconsistent between tools (`v` prefix present for dua, absent for glow) and
  are the easiest thing to get wrong.
- **Deferred**: digest-pinning `ubuntu:24.04` and checksum/signature verification
  of the downloads. Both are real supply-chain gaps; pinning versions is the
  prerequisite step, not the whole answer.
