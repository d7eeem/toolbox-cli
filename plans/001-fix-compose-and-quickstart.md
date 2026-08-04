# Plan 001: Make the README quick-start actually work, and stop tracking `.env`

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 09b4054..HEAD -- compose.yaml README.md .env .dockerignore`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: bug
- **Planned at**: commit `09b4054`, 2026-08-05

## Why this matters

This repo publishes a Docker image full of sysadmin and media tools, but the
three commands the README tells you to run do not work. `docker compose build`
fails because `compose.yaml` declares no build context. `docker exec -it toolbox
bash` fails because no `container_name` is set, so the real container is named
`toolbox-cli-toolbox-1`. And most importantly the service mounts **no volumes**,
so even once you get a shell, the container cannot see a single file on the
host — which makes `ncdu`, `dua`, `yazi`, `ffmpeg`, and `exiftool` pointless.
Anyone who clones this repo and follows the README hits three failures in a row.

Separately, `.env` is committed to git and no `.gitignore` exists. The file
currently holds nothing but a single comment line — **there is no secret in it
today** — but because it is tracked and unignored, the first real value anyone
writes there gets published. This plan removes it from tracking before that
happens.

## Current state

Files involved, and their role:

- `compose.yaml` — the entire compose definition; 3 lines, image reference only.
- `README.md` — the user-facing quick-start; documents commands that fail.
- `.env` — tracked, unignored, contains one comment line and nothing else.
- `.dockerignore` — already excludes `.env`; line 4 references a `.gitignore`
  file that does not exist in this repo.

`compose.yaml` in full, as it exists today (all 3 lines):

```yaml
services:
  toolbox:
    image: ghcr.io/d7eeem/toolbox-cli:latest
```

`README.md:13-30`, as it exists today:

```markdown
## Quick start

```bash
docker compose up -d
docker exec -it toolbox bash
```

## Building

```bash
docker compose build
```

The image is tagged for GitHub Container Registry by default. Update `compose.yaml` to point to your registry of choice.

## Configuration

Yazi configuration lives in `config/yazi/` and is baked into the image at build time. To customize, edit the files in `config/yazi/` and rebuild.
```

`.dockerignore` in full, as it exists today:

```
.env
.git
.github
.gitignore
.DS_Store
*.md
```

Proof of the problem — `docker compose config` on the current file emits a
service with no `container_name`, no `volumes`, no `build`, and no tty:

```
name: toolbox-cli
services:
  toolbox:
    image: ghcr.io/d7eeem/toolbox-cli:latest
    networks:
      default: null
```

**Repo conventions.** There is no application code, no linter, and no test
suite — this repo is a Dockerfile, a compose file, a CI workflow, and baked-in
yazi config. Commit messages are plain lowercase imperative with no
conventional-commit prefix; real examples from `git log`:

```
fix yazi breaking changes
add Dependabot for auto-updating GitHub Actions
bump actions to latest versions (Node 24 compat)
```

Match that style. YAML in this repo uses 2-space indentation (see
`.github/workflows/docker-build.yml`).

**Design decision already made — do not re-litigate it.** The default mount is
the host `$HOME`, overridable via a `TOOLBOX_MOUNT` variable. This was chosen
deliberately: this is a personal sysadmin toolbox, and requiring setup before
`ncdu`/`dua`/`yazi` can see anything defeats the purpose. Implement exactly
that; do not substitute a narrower default.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Validate compose | `docker compose config` | exit 0, prints resolved config |
| Validate compose (JSON) | `docker compose config --format json` | exit 0, prints JSON |
| Check tracked files | `git ls-files` | lists tracked paths |
| Check ignore status | `git check-ignore -v .env` | exit 0 once ignored |

There is no build, test, lint, or typecheck command in this repo. `docker
compose config` is the verification gate for this plan. It parses and resolves
the compose file **without contacting the Docker daemon and without building
anything** — it is safe and fast. Do **not** run `docker compose build` or
`docker compose up`: building this image downloads ffmpeg, imagemagick and
neovim and takes many minutes.

## Scope

**In scope** (the only files you should modify or create):

- `compose.yaml` (modify)
- `README.md` (modify)
- `.gitignore` (create)
- `.env.example` (create)
- `.env` (remove from git tracking only — see Step 3; do NOT delete the file from disk)

**Out of scope** (do NOT touch, even though they look related):

- `Dockerfile` — a separate plan (002) modifies it. Editing it here creates a
  merge conflict.
- `config/yazi/**` — a separate plan (003) modifies it.
- `.github/workflows/docker-build.yml` — plan 002 owns this file.
- `.dockerignore` — it already excludes `.env` correctly. Its line 4 mentions a
  `.gitignore` that does not exist yet; after Step 3 creates one, that line
  becomes correct on its own. No edit needed.

## Git workflow

- Branch: `advisor/001-fix-compose-and-quickstart`
- One commit for the whole plan is fine; message style is lowercase imperative
  with no prefix, e.g. `fix compose quick-start and untrack .env`
- Do NOT push or open a PR.

## Steps

### Step 1: Rewrite `compose.yaml`

Replace the entire contents of `compose.yaml` with exactly this:

```yaml
services:
  toolbox:
    build:
      context: .
    image: ghcr.io/d7eeem/toolbox-cli:latest
    container_name: toolbox
    stdin_open: true
    tty: true
    working_dir: /work
    volumes:
      - ${TOOLBOX_MOUNT:-${HOME}}:/work
```

Notes on why each line is here, so you do not "simplify" any of them away:

- `build.context: .` — makes `docker compose build` work at all.
- `image:` is kept alongside `build:` on purpose: it names the tag that
  `docker compose build` produces and the image `docker compose pull` fetches.
- `container_name: toolbox` — makes the README's `docker exec -it toolbox bash`
  resolve. Without it the container is named `toolbox-cli-toolbox-1`.
- `stdin_open` + `tty` — without these an interactive shell exits immediately.
- `${TOOLBOX_MOUNT:-${HOME}}` — nested interpolation. This form is **verified
  working** on Docker Compose; do not rewrite it as `$HOME` or `${HOME}` alone,
  and do not add quotes around it.

**Verify**: `docker compose config --format json | python3 -c "import json,sys,os; s=json.load(sys.stdin)['services']['toolbox']; assert s['container_name']=='toolbox', s.get('container_name'); assert s['tty'] is True and s['stdin_open'] is True; assert 'build' in s; assert s['working_dir']=='/work'; v=s['volumes'][0]; assert v['source']==os.environ['HOME'], v['source']; assert v['target']=='/work'; print('COMPOSE DEFAULT OK')"`
→ prints `COMPOSE DEFAULT OK`

**Verify the override also works**: `TOOLBOX_MOUNT=/srv/data docker compose config --format json | python3 -c "import json,sys; v=json.load(sys.stdin)['services']['toolbox']['volumes'][0]; assert v['source']=='/srv/data', v['source']; print('COMPOSE OVERRIDE OK')"`
→ prints `COMPOSE OVERRIDE OK`

### Step 2: Create `.env.example`

Create a new file `.env.example` with exactly this content:

```
# Host directory mounted into the container at /work.
# Defaults to your home directory when unset.
# TOOLBOX_MOUNT=/home/you/projects
```

Leave the variable commented out — the default in `compose.yaml` is what should
apply out of the box.

**Verify**: `test -f .env.example && grep -q 'TOOLBOX_MOUNT' .env.example && echo ENV_EXAMPLE_OK`
→ prints `ENV_EXAMPLE_OK`

### Step 3: Create `.gitignore` and untrack `.env`

Create a new file `.gitignore` with exactly this content:

```
.env
.DS_Store
```

Then remove `.env` from git's index **without deleting it from disk**:

```bash
git rm --cached .env
```

`git rm --cached` (not `git rm`) is required — the file must survive on disk so
that anyone with local overrides keeps them; only the tracking is removed.

**Verify**: `git check-ignore -v .env && test -f .env && ! git ls-files --error-unmatch .env 2>/dev/null && echo ENV_UNTRACKED_OK`
→ prints a `.gitignore:1:.env  .env` line followed by `ENV_UNTRACKED_OK`

If that compound command is awkward in your shell, run the three checks
separately and confirm: `git check-ignore .env` exits 0; `test -f .env` exits 0;
`git ls-files .env` prints nothing.

### Step 4: Update the README

In `README.md`, replace the block currently spanning the `## Quick start`,
`## Building`, and `## Configuration` sections (lines 13–30 in the excerpt
above) with:

```markdown
## Quick start

```bash
docker compose up -d
docker exec -it toolbox bash
```

By default your home directory is mounted at `/work` inside the container,
which is also the working directory. To mount somewhere else, copy
`.env.example` to `.env` and set `TOOLBOX_MOUNT`:

```bash
cp .env.example .env
# then edit .env, e.g. TOOLBOX_MOUNT=/home/you/projects
```

`.env` is gitignored — keep local overrides there, not in `compose.yaml`.

## Using the published image

```bash
docker compose pull
```

Because `compose.yaml` defines a build context, `docker compose up` will build
the image locally if it is not already present. Run `docker compose pull` first
if you want the prebuilt image from the registry instead.

## Building

```bash
docker compose build
```

This takes several minutes — it installs the full ffmpeg and imagemagick
suites. The image is tagged for GitHub Container Registry by default; update
the `image:` field in `compose.yaml` to point at your registry of choice.

## Configuration

Yazi configuration lives in `config/yazi/` and is baked into the image at build
time. To customize, edit the files in `config/yazi/` and rebuild.
```

Leave the rest of the README (title, "Included tools", "Aliases", "License")
exactly as it is.

**Verify**: `grep -q 'TOOLBOX_MOUNT' README.md && grep -q 'docker compose pull' README.md && echo README_OK`
→ prints `README_OK`

## Test plan

This repo has no test suite and no test framework, and adding one is explicitly
out of scope for this plan (a separate plan, 004, covers establishing a CI smoke
test). Verification for this plan is the `docker compose config` gate in Step 1,
which is a real parser check: it resolves interpolation, validates schema, and
fails non-zero on a malformed file.

Do **not** add a test framework, a `package.json`, or a CI job as part of this
plan.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `docker compose config` exits 0
- [ ] `docker compose config --format json` shows `container_name: toolbox`,
      `tty: true`, `stdin_open: true`, `working_dir: /work`, a `build` key, and
      a volume with `source` == `$HOME` and `target` == `/work`
- [ ] `TOOLBOX_MOUNT=/srv/data docker compose config --format json` shows the
      volume `source` as `/srv/data`
- [ ] `git check-ignore .env` exits 0
- [ ] `git ls-files .env` prints nothing (no longer tracked)
- [ ] `test -f .env` exits 0 (still present on disk)
- [ ] `test -f .env.example` exits 0
- [ ] `grep -q TOOLBOX_MOUNT README.md` exits 0
- [ ] `git status --porcelain` shows changes only to: `compose.yaml`,
      `README.md`, `.gitignore`, `.env.example`, `.env` (deletion from index).
      No other path appears.

## STOP conditions

Stop and report back (do not improvise) if:

- `compose.yaml` is not the exact 3 lines shown in "Current state" — the repo
  has drifted and this plan's replacement may discard someone's work.
- `.env` contains anything other than a single comment line. **If it contains
  what looks like a credential, do NOT print its contents in your report** —
  report only that `.env` has unexpected content and stop, so a human can
  rotate the value before it is handled further.
- `docker compose config` fails with an interpolation error on
  `${TOOLBOX_MOUNT:-${HOME}}` — this means the installed Compose version does
  not support nested defaults. Report the exact error and the output of
  `docker compose version`; do not fall back to a different mount expression.
- `git rm --cached .env` reports that the file is not tracked (someone already
  untracked it) — finish the other steps and note it.
- A `.gitignore` already exists — do not overwrite it; report and stop.

## Maintenance notes

For whoever owns this next:

- **`build:` and `image:` together changes `up` behavior.** With a build context
  defined, `docker compose up` builds locally when the tagged image is absent
  rather than pulling. The README now documents `docker compose pull` for the
  registry path. If that trade-off ever becomes annoying, the alternative is a
  compose profile or a second `compose.build.yaml`.
- **The `$HOME` default is a deliberate blast-radius choice.** The container
  runs as root, so anything in it can read and write all of `$HOME`, and files
  it creates on the mount will be root-owned on the host. That root-ownership
  friction is a known, separately-tracked issue; do not try to solve it here
  with a `user:` field, which would break the image's baked-in `/root/.config`.
- **A reviewer should scrutinize** that `git rm --cached` was used rather than
  `git rm` (the file must still exist on disk), and that no secret value was
  copied into `.env.example`.
- **Deferred on purpose**: adding a CI smoke test that actually runs the image
  and proves the mount works. That belongs in the verification-baseline plan,
  not here.
