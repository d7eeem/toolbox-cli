# Plan 009: Set up Buildx so the GHA cache export works and CI goes green again

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat e2ab713..HEAD -- .github/workflows/docker-build.yml`
> On a mismatch with the "Current state" excerpt, treat it as a STOP condition.

## Status

- **Priority**: P0 — CI is currently red and no image is being published
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: bug
- **Planned at**: commit `e2ab713`, 2026-08-05

## Why this matters

CI is failing on every push, at the `Build` step, before the smoke test even
runs. Nothing has been published since commit `d886adb`, which means the `ya`
binary fix from plan 004 is **merged but not live** — the image in the registry
still cannot extract archives.

The cause is a defect introduced by plan 005. That plan split the workflow into
Build → Smoke test → Push and added `cache-from: type=gha` /
`cache-to: type=gha,mode=max` to both build steps, so the push step could reuse
the layers the build step produced instead of rebuilding from scratch. But it
did **not** add a `docker/setup-buildx-action` step.

Without that, the runner uses Buildx's default `docker` driver, which cannot
export a cache. The build fails with:

```
buildx failed with: Learn more at https://docs.docker.com/go/build-cache-backends/
```

(That link is the tell — it is emitted with "Cache export is not supported for
the docker driver. Switch to a different driver, or turn on the containerd image
store, and try again.")

Adding the Buildx setup step switches the builder to the `docker-container`
driver, which supports both GHA cache export and `load: true`.

Evidence — run `30962139525` on commit `07ebfe7`, job `build`:

```
 1. success    Set up job
 2. success    Run actions/checkout@v7.0.1
 3. success    Log in to GitHub Container Registry
 4. failure    Build
 5. skipped    Smoke test
 6. skipped    Push
```

The last successful run was `d886adb`, the commit immediately before plan 005
landed.

## Current state

`.github/workflows/docker-build.yml`, lines 20–56, exactly as they exist today:

```yaml
    steps:
      - uses: actions/checkout@v7.0.1

      - name: Log in to GitHub Container Registry
        uses: docker/login-action@v4.5.2
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

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

**Repo conventions.** Every action is pinned to an exact patch version
(`actions/checkout@v7.0.1`, `docker/login-action@v4.5.2`,
`docker/build-push-action@v7.3.0`) — dependabot bumps them weekly via
`.github/dependabot.yml`. Match that: pin the new action to an exact version too,
not a floating major. **The current latest release of
`docker/setup-buildx-action` is `v4.2.0`** (checked while writing this plan).

YAML uses 2-space indentation. Commit messages are plain lowercase imperative
with no conventional-commit prefix; real examples from `git log`:

```
fix yazi breaking changes
bump actions to latest versions (Node 24 compat)
gate CI on an image smoke test
```

## Commands you will need

| Purpose | Command | Expected |
|---|---|---|
| Validate workflow YAML | `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/docker-build.yml')); print('YAML OK')"` | prints `YAML OK` |

This repo has no build, test, lint, or typecheck command. Do **not** run
`docker build` — this image installs the full ffmpeg and imagemagick suites and
takes many minutes. The real verification for this plan is the CI run itself,
which the reviewer will check after merge.

## Scope

**In scope** (the only file you may modify):

- `.github/workflows/docker-build.yml` — add one step; change nothing else

**Out of scope** (do NOT touch, even though they look related):

- **Do not remove `cache-from` / `cache-to`.** Deleting the cache would also
  make the error go away, but it would double CI time, since the Push step would
  rebuild the whole image from scratch. The cache is wanted; the missing builder
  setup is the bug.
- **Do not remove the Build/Smoke test/Push split**, and do not move the smoke
  test after the push. That ordering is the entire point of plan 005.
- `test/smoke.sh` — it never ran, so nothing about it is known to be wrong. Leave
  it alone.
- `Dockerfile`, `compose.yaml`, `README.md`, `config/yazi/**`, `plans/**`.

## Git workflow

- Branch: `advisor/009-fix-buildx-cache-driver`
- One commit; message style is lowercase imperative with no prefix, e.g.
  `set up buildx so gha cache export works`
- Do NOT push or open a PR.

## Steps

### Step 1: Add the Buildx setup step

Insert a new step **after** the `Log in to GitHub Container Registry` step and
**before** the `Build` step:

```yaml
      - name: Set up Buildx
        uses: docker/setup-buildx-action@v4.2.0
```

Placement matters: it must come before the first `build-push-action` step, or
that step still runs on the default driver. It may come before or after the
login step; after is conventional.

Change nothing else in the file.

**Verify the step exists, is correctly placed, and everything else survived**:

```bash
python3 -c "
import yaml
d=yaml.safe_load(open('.github/workflows/docker-build.yml'))
steps=d['jobs']['build']['steps']
names=[s.get('name') for s in steps]
uses=[s.get('uses','') for s in steps]

bx=[i for i,u in enumerate(uses) if u.startswith('docker/setup-buildx-action@')]
assert len(bx)==1, f'expected exactly one setup-buildx-action, got {len(bx)}'
assert uses[bx[0]]=='docker/setup-buildx-action@v4.2.0', uses[bx[0]]

bi=names.index('Build')
assert bx[0] < bi, 'setup-buildx must come before the Build step'

# the plan-005 structure must be intact
assert names.index('Build') < names.index('Smoke test') < names.index('Push')
b=steps[bi]['with']
p=steps[names.index('Push')]
assert b['load'] is True and b['push'] is False
assert p['with']['push'] is True and 'pull_request' in p['if']
assert b['cache-to']=='type=gha,mode=max' and b['cache-from']=='type=gha'
assert p['with']['cache-to']=='type=gha,mode=max'
assert b['tags']==p['with']['tags']
print('WORKFLOW OK')"
```

→ prints `WORKFLOW OK`

**Verify the action is pinned to an exact version, not a floating major**:
`grep -c 'setup-buildx-action@v4\.2\.0' .github/workflows/docker-build.yml`
→ prints `1`

**Verify the token is still used only for login**:
`grep -c 'secrets.GITHUB_TOKEN' .github/workflows/docker-build.yml` → prints `1`

### Step 2: Confirm nothing else changed

**Verify**: `git diff --stat` → shows exactly one file changed, with 2 insertions
and 0 deletions.

If the diff shows any deletion, you have modified an existing line. Undo it —
this plan adds a step and nothing more.

## Test plan

This repo's test infrastructure is `test/smoke.sh`, run in CI. It is not
runnable here (it needs a built image, which takes many minutes) and it is not
what this plan changes.

Verification is therefore in two parts:

1. **Structural, local** — the Step 1 assertion is deliberately broad: as well as
   checking the new step exists and precedes `Build`, it re-asserts the entire
   plan-005 structure (step order, `load`/`push` flags, both cache settings,
   matching tags, the PR guard). A regression anywhere in the workflow fails it.
2. **Behavioural, post-merge** — the authoritative check is the CI run. After
   this merges, the `Build` step must succeed and the `Smoke test` step must
   actually execute. **The reviewer owns this check**; do not attempt it here.

Do **not** add a test framework, a `package.json`, or a new CI job.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `python3 -c "import yaml; yaml.safe_load(...)"` prints `YAML OK`
- [ ] The Step 1 assertion prints `WORKFLOW OK`
- [ ] `grep -c 'setup-buildx-action@v4\.2\.0' .github/workflows/docker-build.yml` prints `1`
- [ ] `grep -c 'secrets.GITHUB_TOKEN' .github/workflows/docker-build.yml` prints `1`
- [ ] `git diff --stat` shows 1 file, 2 insertions, 0 deletions
- [ ] `git status --porcelain` shows a change only to
      `.github/workflows/docker-build.yml`

## STOP conditions

Stop and report back (do not improvise) if:

- The workflow file does not match the "Current state" excerpt.
- `git diff` shows any deleted line.
- You conclude the fix should be to remove `cache-to`/`cache-from` instead. It
  should not — that trades a doubled CI build time for a one-line step. If you
  believe the cache genuinely cannot work here, stop and explain rather than
  removing it.
- The Step 1 assertion fails on any part of the plan-005 structure — that means
  something other than your edit is wrong, and the reviewer needs to know.

## Maintenance notes

For whoever owns this next:

- **`docker/build-push-action` needs an explicit builder whenever you use
  `cache-to`, multi-platform builds, or any non-default exporter.** The default
  `docker` driver silently supports none of them. If a future change adds
  `platforms:` or another cache backend and CI starts failing with a
  `build-cache-backends` link, this is the same class of problem.
- **Dependabot now has a fourth action to bump.** `setup-buildx-action` is pinned
  to `v4.2.0`; expect a PR when v4.3.0 ships.
- **A reviewer should scrutinize** that the new step sits before `Build` — a
  correctly-pinned step in the wrong position looks right and fails identically.
- **This bug hid a second one.** The smoke test from plan 005 has never
  executed, so its tool list is entirely unvalidated. Once CI gets past `Build`,
  the first `Smoke test` run may still fail on a binary-name mismatch
  (`ffprobe`, `ffmpegthumbnailer`, and `exiftool` are the likeliest). That would
  be a *different* fix — adding an alternative like `a|b` to the `TOOLS` list —
  and must not be worked around by weakening the test.
