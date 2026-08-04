# Plan 008: Run as a non-root user and harden the container for always-on use

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat d886adb..HEAD -- Dockerfile compose.yaml README.md .env.example`
> On a mismatch with the "Current state" excerpts, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: **HIGH** — this is the only plan in this set that changes behavior
  for existing deployments. Read "Breaking changes" before starting.
- **Depends on**: plans/005-image-smoke-test.md (**hard**), plans/006-truenas-docs.md (soft)
- **Category**: security
- **Planned at**: commit `d886adb`, 2026-08-05
- **NOT YET EXECUTED** — written for later execution, deliberately held back
  because it is breaking.

## Breaking changes — read first

1. **Config path moves.** Baked-in yazi config moves from `/root/.config` to
   `/home/toolbox/.config`. Anyone who has `docker exec`'d in and edited config
   at the old path loses those edits on the next image pull.
2. **File ownership changes.** Files the container creates in a mounted volume
   become owned by `PUID:PGID` (default `1000:1000`) instead of `root`. This is
   the *point* of the change, but existing root-owned files stay root-owned and
   may become unwritable by the container.
3. **Changing `PUID`/`PGID` requires a rebuild**, not a restart — the user is
   created at build time.
4. **Root-only operations stop working** inside the container: `apt-get install`,
   writing outside the mount, binding low ports. For a sysadmin toolbox this may
   be a real loss; see "Open question" below.

**Open question the maintainer must answer before this is executed**: is
losing in-container `apt-get` acceptable? A toolbox where you cannot install an
extra tool on the fly is meaningfully less useful. Two viable answers: (a) accept
it, rebuild the image when you need a new tool — the reproducible-build path; or
(b) keep root and solve ownership another way, e.g. run `docker exec -u` for
specific tasks. **Do not execute this plan until that is decided.**

## Why this matters

The container runs as root. On TrueNAS SCALE — the documented target — every
file the toolbox writes into a mounted dataset lands owned by `root:root`. That
is a recurring cleanup chore and can lock other applications out of files the
toolbox touched. The conventional fix for NAS containers is a build-time
`PUID`/`PGID` matching the dataset owner.

This was previously assessed as "by design, not a finding" on the assumption
this was a laptop tool. That assessment was based on a wrong premise — the repo
targets an appliance where dataset ownership genuinely matters.

Alongside it, three small always-on hardening settings are folded in, since they
share the same files and the same "is this an appliance?" premise:
`restart: unless-stopped`, `init: true`, and CPU/memory limits so `ffmpeg` or
`imagemagick` cannot starve the ZFS ARC cache the rest of the box depends on.

## Current state

`Dockerfile:66-72` today (tail of the file):

```dockerfile
# LazyVim
RUN git clone https://github.com/LazyVim/starter ~/.config/nvim

# Config baked into image
COPY config/ /root/.config/

CMD ["sleep", "infinity"]
```

There is no `USER` instruction anywhere in the `Dockerfile`, so the image runs
as root.

`compose.yaml` today has no `restart`, no `init`, and no `deploy` key — confirm
with `docker compose config --format json`.

Ubuntu 24.04's base image **already contains a user named `ubuntu` with UID
1000**, which collides with the common default `PUID=1000`. It must be removed
before creating the new user, or `useradd` fails.

**TrueNAS note**: the `apps` user is commonly `568`, but the *dataset owner* is
what actually matters. Check with `ls -ln /mnt/<pool>/<dataset>`.

**Repo conventions.** Single `RUN` per logical step, `&&`-chained, 4-space
continuation indent. YAML 2-space indent. Commit messages plain lowercase
imperative, no prefix.

## Commands you will need

| Purpose | Command | Expected |
|---|---|---|
| Validate compose | `docker compose config --format json` | exit 0 |
| Grep audit | `grep -n 'USER\|PUID\|/root/.config' Dockerfile` | as specified per step |

Do **not** run `docker build`.

## Scope

**In scope**: `Dockerfile`, `compose.yaml`, `.env.example`, `README.md`.

**Out of scope**:
- Version pinning / SHA tags — plan 007.
- `config/yazi/**` — the config content is correct; only where it is *copied to*
  changes.
- `.github/workflows/**` and `test/smoke.sh` — but see STOP conditions: the smoke
  test must still pass as a non-root user, and if it does not, that is a finding
  to report, not something to patch here.

## Git workflow

- Branch: `advisor/008-non-root-and-hardening`
- Commit per step is fine; lowercase imperative messages, no prefix.
- Do NOT push or open a PR.

## Steps

### Step 1: Add build args for the user

Insert after `Dockerfile:2` (`ENV DEBIAN_FRONTEND=noninteractive`):

```dockerfile
ARG PUID=1000
ARG PGID=1000
ARG USERNAME=toolbox
```

**Verify**: `grep -c '^ARG PUID=1000' Dockerfile` prints `1`.

### Step 2: Create the user, removing Ubuntu's colliding default

Insert immediately before the `# LazyVim` block:

```dockerfile
# Non-root user — files created in mounted volumes get this ownership.
# Ubuntu 24.04 ships a stock `ubuntu` user at UID 1000 that must go first.
RUN userdel -r ubuntu 2>/dev/null || true \
    && groupadd -g ${PGID} ${USERNAME} \
    && useradd -u ${PUID} -g ${PGID} -m -s /bin/bash ${USERNAME}
```

The `|| true` is required: on a base image where `ubuntu` does not exist,
`userdel` exits non-zero and would fail the build.

**Verify**: `grep -c 'userdel -r ubuntu' Dockerfile` prints `1`.

### Step 3: Move LazyVim and the baked config to the new home

Replace the `# LazyVim` and `# Config baked into image` blocks with:

```dockerfile
# LazyVim
RUN git clone https://github.com/LazyVim/starter /home/${USERNAME}/.config/nvim

# Config baked into image
COPY --chown=${PUID}:${PGID} config/ /home/${USERNAME}/.config/

RUN chown -R ${PUID}:${PGID} /home/${USERNAME}

USER ${USERNAME}
WORKDIR /home/${USERNAME}

CMD ["sleep", "infinity"]
```

`COPY --chown` handles the copied files; the explicit `chown -R` catches the
`git clone` output, which runs as root.

**Verify**: `grep -c '/root/.config' Dockerfile` returns 0 matches;
`grep -c '^USER ${USERNAME}' Dockerfile` prints `1`.

**Verify `USER` is the last instruction before `CMD`**:
```bash
python3 -c "
ls=[l.strip() for l in open('Dockerfile') if l.strip() and not l.strip().startswith('#')]
i=[n for n,l in enumerate(ls) if l.startswith('USER ')]
assert len(i)==1, i
assert ls[-1].startswith('CMD'), ls[-1]
assert i[0] < len(ls)-1
print('USER PLACEMENT OK')"
```
→ prints `USER PLACEMENT OK`

### Step 4: Wire PUID/PGID and hardening through compose

Update `compose.yaml` to add build args and the always-on settings, leaving the
existing volume entry untouched:

```yaml
    build:
      context: .
      args:
        PUID: ${PUID:-1000}
        PGID: ${PGID:-1000}
    restart: unless-stopped
    init: true
    deploy:
      resources:
        limits:
          cpus: "4.0"
          memory: 4G
```

**Verify**:
```bash
docker compose config --format json | python3 -c "
import json,sys,os
s=json.load(sys.stdin)['services']['toolbox']
assert s['restart']=='unless-stopped', s.get('restart')
assert s['init'] is True
assert s['build']['args']['PUID']=='1000', s['build']['args']
v=s['volumes']; assert len(v)==1 and v[0]['target']=='/work'
print('COMPOSE OK')"
```
→ prints `COMPOSE OK`

### Step 5: Document it

Add `PUID`/`PGID` examples to `.env.example` (commented), and a
`## Running as non-root` section to `README.md` covering: how to find the right
UID (`ls -ln /mnt/<pool>/<dataset>`), that TrueNAS commonly uses `568` but the
dataset owner is authoritative, that changing it needs `docker compose build`
not a restart, and that `apt-get` inside the container no longer works.

Also update the sentence added by plan 006 that says non-root is "tracked as a
separate change" — it is no longer pending.

**Verify**: `grep -c 'Running as non-root' README.md` prints `1`;
`grep -c 'tracked as a separate change' README.md` returns 0 matches.

## Test plan

The substantive test is plan 005's CI smoke test, re-run against the non-root
image. Every tool must still resolve on `PATH` for an unprivileged user — this
is the check that catches a botched `chown` or a tool installed into a
root-only path.

Additionally verify by inspection that no step in `test/smoke.sh` requires root.
As of plan 005 it only runs `command -v` and `--version`, so it should pass
unchanged. **If it does not, report it — do not weaken the smoke test.**

Plan-local verification is the Step 3 `USER`-placement assertion (a `USER` line
in the wrong place silently leaves later layers running as root) and the Step 4
compose assertion.

## Done criteria

- [ ] `grep -c '/root/.config' Dockerfile` returns 0 matches
- [ ] Exactly one `USER` instruction, and it is the last non-comment instruction before `CMD`
- [ ] `grep -c 'userdel -r ubuntu' Dockerfile` prints `1`
- [ ] `ARG PUID`, `ARG PGID`, `ARG USERNAME` all present
- [ ] Compose resolves `restart: unless-stopped`, `init: true`, `build.args.PUID`, and still exactly one volume at `/work`
- [ ] `grep -c 'Running as non-root' README.md` prints `1`
- [ ] `grep -c 'tracked as a separate change' README.md` returns 0 matches
- [ ] `git status --porcelain` shows only `Dockerfile`, `compose.yaml`, `.env.example`, `README.md`

## STOP conditions

- The maintainer has not answered the "Open question" about losing in-container
  `apt-get`. Stop before writing any code.
- Plan 005 is not merged at your branch point.
- `test/smoke.sh` would need modifying to pass as non-root — report which tool
  fails and why; do not weaken the test.
- A "Current state" excerpt does not match the live file.
- The `USER`-placement assertion fails.
- You find yourself adding `sudo` to the image to work around lost root. That
  re-opens the hole this plan closes — stop and report instead.

## Maintenance notes

- **UID is baked at build time.** Every `PUID`/`PGID` change needs
  `docker compose build`. A restart silently keeps the old UID — expect this to
  confuse people; it is why the README section is required, not optional.
- **`userdel -r ubuntu` is base-image-specific.** If the base ever moves off
  Ubuntu 24.04, re-check whether a UID-1000 user still ships by default.
- **A reviewer should scrutinize** the `USER` placement (anything after it that
  needs root will fail at build time) and the `chown -R`, which must cover the
  `git clone` output as well as the `COPY`.
- **Deferred**: rootless Docker, user namespace remapping, and dropping Linux
  capabilities. All are further hardening; none are prerequisites for fixing
  file ownership, which is the actual pain point.
