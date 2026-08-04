# Plan 006: Document the TrueNAS SCALE deployment path (additive only)

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat d886adb..HEAD -- README.md compose.yaml .env.example`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: docs
- **Planned at**: commit `d886adb`, 2026-08-05

## Why this matters

This image is aimed at TrueNAS SCALE — an always-on storage appliance where you
cannot install native packages, and anything you did install would not survive
an OS update. A persistent container you `docker exec` into is the durable way
to keep these tools available on such a box. None of that reasoning is recorded
anywhere in the repo: `README.md` describes a generic "portable CLI toolbox" and
`compose.yaml` defaults to mounting the host `$HOME`, which on a NAS is not where
any of the data lives.

The result is that someone deploying this on a NAS gets a container that can see
their home directory and none of their pools, with no documentation explaining
what to change.

This plan is **documentation and commented examples only**. It deliberately does
not change any default or any runtime behavior — the `$HOME` mount stays exactly
as it is, so existing setups are unaffected. Readers get a clearly signposted
path to dataset mounts; nobody's working configuration changes underneath them.

## Current state

`compose.yaml` in full, exactly as it exists today:

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

`.env.example` in full, exactly as it exists today:

```
# Host directory mounted into the container at /work.
# Defaults to your home directory when unset.
# TOOLBOX_MOUNT=/home/you/projects
```

`README.md` currently has these sections in order: title, "Included tools",
"Quick start", "Using the published image", "Building", "Configuration",
"Aliases (included in image)", "License". The "Configuration" section reads:

```markdown
## Configuration

Yazi configuration lives in `config/yazi/` and is baked into the image at build
time. To customize, edit the files in `config/yazi/` and rebuild.
```

**Repo conventions.** Markdown prose in `README.md` is hard-wrapped at roughly
80 columns in the recently-edited sections. YAML uses 2-space indentation.
Commit messages are plain lowercase imperative with no conventional-commit
prefix; real examples from `git log`:

```
add Dependabot for auto-updating GitHub Actions
fix yazi breaking changes
bump actions to latest versions (Node 24 compat)
```

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Validate compose | `docker compose config` | exit 0 |
| Validate compose (JSON) | `docker compose config --format json` | exit 0 |

`docker compose config` parses and resolves the file without contacting the
Docker daemon and without building anything. Do **not** run `docker compose
build` or `docker compose up`.

## Scope

**In scope**:

- `README.md` (modify — add one new section; adjust nothing else)
- `compose.yaml` (modify — add comments only)
- `.env.example` (modify — add a commented example line)

**Out of scope** (do NOT touch, even though they look related):

- **The `volumes:` value itself.** `${TOOLBOX_MOUNT:-${HOME}}:/work` must remain
  exactly as it is. This plan is explicitly non-breaking; changing the default
  mount would alter behavior for anyone already running this. Add commented
  examples *beside* it, never in place of it.
- **`restart:`, `init:`, and `deploy.resources.limits`.** These are real
  improvements for an always-on appliance, but each changes runtime behavior and
  belongs to a separate deployment-hardening plan. Do not add them here.
- Non-root / `PUID` / `PGID` — separate plan, and it requires a `Dockerfile`
  change.
- `Dockerfile`, `.github/workflows/**`, `config/yazi/**`, `test/**`.

## Git workflow

- Branch: `advisor/006-truenas-docs`
- One commit; message style is lowercase imperative with no prefix, e.g.
  `document TrueNAS SCALE deployment and dataset mounts`
- Do NOT push or open a PR.

## Steps

### Step 1: Add commented dataset examples to `compose.yaml`

Modify **only** the `volumes:` block, leaving its existing entry untouched, so
the file reads:

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
      # Default: your home directory, overridable with TOOLBOX_MOUNT in .env.
      - ${TOOLBOX_MOUNT:-${HOME}}:/work
      # On TrueNAS SCALE, mount the datasets you want the toolbox to reach
      # instead. Pool and dataset names are specific to your installation —
      # edit these before uncommenting, and see "Deploying on TrueNAS SCALE"
      # in README.md.
      # - /mnt/tank/media:/work/media
      # - /mnt/tank/downloads:/work/downloads
```

The single active volume entry is unchanged. Everything added is a comment.

**Verify the resolved config is byte-for-byte unchanged in behavior** — this is
the critical check for a non-breaking plan:

```bash
docker compose config --format json | python3 -c "
import json,sys,os
s=json.load(sys.stdin)['services']['toolbox']
v=s['volumes']
assert len(v)==1, f'expected exactly 1 active volume, got {len(v)}'
assert v[0]['source']==os.environ['HOME'], v[0]['source']
assert v[0]['target']=='/work'
assert s['container_name']=='toolbox' and s['working_dir']=='/work'
assert s['tty'] is True and s['stdin_open'] is True
assert 'restart' not in s, 'restart policy is out of scope'
assert 'deploy' not in s, 'resource limits are out of scope'
print('COMPOSE UNCHANGED OK')"
```

→ prints `COMPOSE UNCHANGED OK`

**Verify the override still works**:
`TOOLBOX_MOUNT=/mnt/tank docker compose config --format json | python3 -c "import json,sys; v=json.load(sys.stdin)['services']['toolbox']['volumes'][0]; assert v['source']=='/mnt/tank', v['source']; print('OVERRIDE OK')"`
→ prints `OVERRIDE OK`

### Step 2: Add a dataset example to `.env.example`

Append to `.env.example` so it reads in full:

```
# Host directory mounted into the container at /work.
# Defaults to your home directory when unset.
# TOOLBOX_MOUNT=/home/you/projects

# On TrueNAS SCALE, point this at a pool path instead, e.g.:
# TOOLBOX_MOUNT=/mnt/tank
```

Both lines stay commented — the default must remain in effect.

**Verify no line is uncommented**:
`grep -vE '^\s*(#|$)' .env.example | wc -l` → prints `0`

### Step 3: Add the TrueNAS section to `README.md`

Insert a new section **immediately after** the existing `## Configuration`
section and **before** `## Aliases (included in image)`:

```markdown
## Deploying on TrueNAS SCALE

This image targets TrueNAS SCALE, an always-on storage appliance where you
can't install native packages and anything you did install wouldn't survive an
OS update. A persistent container you `docker exec` into is the durable way to
keep these tools around.

Two things differ from a desktop setup:

**Mount your datasets, not your home directory.** The default mount is the host
`$HOME`, which on a NAS is not where your data lives. Either set `TOOLBOX_MOUNT`
in `.env` to a pool path:

```bash
TOOLBOX_MOUNT=/mnt/tank
```

or uncomment and edit the per-dataset examples in `compose.yaml` for finer
control over what the container can reach. Pool and dataset names are specific
to your installation, so nothing is mounted by default.

**Files are created as root.** The container runs as root, so anything it writes
into a mounted dataset is owned by `root`. If that conflicts with how other apps
access those datasets, you will need to `chown` afterwards. Running as a
non-root user with a matching UID/GID is tracked as a separate change.
```

Note the nested code fence: when you write this into `README.md`, the ```bash
block stays as a normal fenced block — do not escape or indent it.

Leave every other section of `README.md` exactly as it is.

**Verify**: `grep -c 'TrueNAS SCALE' README.md` → prints at least `1`

**Verify section ordering**:
```bash
python3 -c "
t=open('README.md').read()
for a,b in [('## Configuration','## Deploying on TrueNAS SCALE'),('## Deploying on TrueNAS SCALE','## Aliases')]:
    assert t.index(a) < t.index(b), (a,b)
print('README ORDER OK')"
```
→ prints `README ORDER OK`

## Test plan

This repo's test infrastructure is a CI image smoke test (plan 005); it checks
binaries in the built image and has no bearing on documentation. No new
automated test is appropriate here, and none should be added.

Verification for this plan is instead a **behavioral-invariance check**, which
is the substantive gate given the plan's non-breaking promise:

- Step 1 asserts the resolved compose config still has exactly **one** active
  volume, still pointing at `$HOME` → `/work`, with no `restart` or `deploy` key
  introduced. If any commented example were accidentally left active, or any
  out-of-scope key added, this fails.
- Step 2 asserts `.env.example` contains zero non-comment lines.
- Step 3 asserts the new section exists and is correctly positioned.

Do **not** add a test framework, a `package.json`, or a new CI job.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `docker compose config` exits 0
- [ ] Resolved config has exactly 1 volume, `source` == `$HOME`, `target` == `/work`
- [ ] Resolved config has no `restart` and no `deploy` key
- [ ] `TOOLBOX_MOUNT=/mnt/tank docker compose config` resolves `source` to `/mnt/tank`
- [ ] `grep -vE '^\s*(#|$)' .env.example | wc -l` prints `0`
- [ ] `grep -c 'TrueNAS SCALE' README.md` is at least 1
- [ ] The README section-order assertion prints `README ORDER OK`
- [ ] `git diff --stat` shows changes only to `README.md`, `compose.yaml`,
      `.env.example`
- [ ] `git diff compose.yaml` shows **only added comment lines** — no
      modification or deletion of any existing line

## STOP conditions

Stop and report back (do not improvise) if:

- `compose.yaml`, `.env.example`, or the `## Configuration` section of
  `README.md` does not match the "Current state" excerpts.
- The compose invariance check fails — in particular if more than one active
  volume is resolved. That means an example was left uncommented, which would
  break someone's deployment by mounting a path that may not exist.
- You conclude the default mount "should" be changed to a dataset path. It
  should not, in this plan. That is a deliberate product decision left open;
  changing it here would break existing setups.
- You are tempted to add `restart: unless-stopped` or resource limits because
  the README text mentions an always-on appliance. Do not — they are explicitly
  out of scope and change runtime behavior.

## Maintenance notes

For whoever owns this next:

- **This plan documents a situation it does not resolve.** The repo now says
  "targets TrueNAS SCALE" while defaulting to a `$HOME` mount that suits a
  desktop. That is a deliberate, reversible middle ground, not an oversight. The
  open decision is whether this image is a NAS tool, a desktop tool, or both —
  and the default should be revisited once that is settled.
- **The README now promises a non-root option is "tracked as a separate
  change."** If that work is abandoned, remove the sentence rather than leaving
  a dangling promise.
- **A reviewer should scrutinize** the `git diff` of `compose.yaml` specifically:
  every line in it must be an addition starting with `#`. Any modified or
  deleted line means the non-breaking guarantee was violated.
- **Deliberately deferred**: `restart: unless-stopped`, `init: true`,
  `deploy.resources.limits` (which matter on an appliance where `ffmpeg` can
  starve the ZFS ARC cache), non-root `PUID`/`PGID`, and immutable SHA image
  tags for rollback. Each changes behavior and needs its own plan.
