# Plan 002: Stop baking `GITHUB_TOKEN` into the published image's build history

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 09b4054..HEAD -- Dockerfile .github/workflows/docker-build.yml`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: security
- **Planned at**: commit `09b4054`, 2026-08-05

## Why this matters

The CI workflow passes `secrets.GITHUB_TOKEN` into `docker build` as a
**build argument**. BuildKit records build-arg values in the resulting layer's
`created_by` metadata, which means the token string is embedded in the image and
readable by anyone who runs `docker history` against the published image. Docker's
own documentation warns against exactly this: build-time variables "are visible
to any user of the image with the docker history command." This image is pushed
to a public registry on every push to `main`.

The practical severity is bounded — a GitHub Actions `GITHUB_TOKEN` is ephemeral
and is revoked when the job ends — so this is not a standing credential leak. But
it publishes a then-valid token, and the fix removes the exposure entirely at
near-zero cost.

The token exists only to avoid GitHub API rate limits while resolving the latest
`dua-cli` version number. That API call is unnecessary: GitHub's
`/releases/latest` URL issues a redirect to the versioned tag URL, and reading
that redirect requires no authentication and is not rate-limited the same way.
Removing the API call removes the need for the token, which removes the leak.

## Current state

Files involved:

- `Dockerfile` — the `dua-cli` install block declares `ARG GITHUB_TOKEN` and
  uses it to authenticate a GitHub API call (lines 41–51).
- `.github/workflows/docker-build.yml` — passes the secret in as a build-arg
  (lines 36–37).

`Dockerfile:41-51`, as it exists today:

```dockerfile
# dua-cli — uses API to resolve version; pass GITHUB_TOKEN as build-arg to avoid rate limits
ARG GITHUB_TOKEN=""
RUN DUA_VERSION=$(curl -s \
        ${GITHUB_TOKEN:+-H "Authorization: Bearer $GITHUB_TOKEN"} \
        https://api.github.com/repos/Byron/dua-cli/releases/latest \
        | jq -r '.tag_name' | sed 's/v//') \
    && wget -qO /tmp/dua.tar.gz \
        "https://github.com/Byron/dua-cli/releases/latest/download/dua-v${DUA_VERSION}-x86_64-unknown-linux-musl.tar.gz" \
    && tar xzf /tmp/dua.tar.gz -C /tmp \
    && find /tmp -name dua -type f -exec mv {} /usr/local/bin/ \; \
    && rm -rf /tmp/dua*
```

`.github/workflows/docker-build.yml:30-37`, as it exists today:

```yaml
      - name: Build and push
        uses: docker/build-push-action@v7.3.0
        with:
          context: .
          push: ${{ github.event_name != 'pull_request' }}
          tags: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:latest
          build-args: |
            GITHUB_TOKEN=${{ secrets.GITHUB_TOKEN }}
```

**The replacement technique, already verified working.** These exact commands
were run against the live GitHub endpoints while writing this plan:

```
$ curl -sILo /dev/null -w '%{url_effective}\n' https://github.com/Byron/dua-cli/releases/latest
https://github.com/Byron/dua-cli/releases/tag/v2.41.1

$ curl -sIo /dev/null -w '%{http_code}' -L "https://github.com/Byron/dua-cli/releases/latest/download/dua-v2.41.1-x86_64-unknown-linux-musl.tar.gz"
200
```

So: follow the redirect, strip everything up to and including `/tag/v`, and you
have the bare version number the asset filename needs. No token, no `jq`, no API.

**Repo conventions.** The Dockerfile already installs three tools from GitHub
releases (`eza` at line 35, `dua` at 43, `yazi` at 54). Each is a single `RUN`
with `&&`-chained steps, 4-space continuation indent, and a `rm -rf /tmp/<name>*`
cleanup at the end. Match that shape exactly. Commit messages are plain lowercase
imperative with no conventional-commit prefix — real examples from `git log`:

```
fix yazi breaking changes
remove GitHub API calls from build, use direct /latest/download/ URLs instead
bump actions to latest versions (Node 24 compat)
```

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Validate workflow YAML | `python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/docker-build.yml')); print('YAML OK')"` | prints `YAML OK` |
| Version resolution check | see Step 1 verify block | prints a version and `200` |
| Grep audit | `grep -n GITHUB_TOKEN Dockerfile .github/workflows/docker-build.yml` | only the login line remains |

This repo has no build, test, lint, or typecheck command. Do **not** run
`docker build` to verify — building this image downloads the full ffmpeg and
imagemagick suites and takes many minutes. The Step 1 verification runs the
*exact shell pipeline* that will run inside the `RUN` instruction, on the host,
using only `curl` and `sed` — which proves the logic without a build.

If `python3` is unavailable, `python -c` is an acceptable substitute for the
YAML check. If neither exists, skip that one check and say so in your report.

## Scope

**In scope** (the only files you should modify):

- `Dockerfile` — only the `dua-cli` block at lines 41–51
- `.github/workflows/docker-build.yml` — only the `build-args` input

**Out of scope** (do NOT touch, even though they look related):

- The `eza` block (`Dockerfile:34-39`) and the `yazi` block
  (`Dockerfile:53-58`) — they already use unauthenticated
  `/latest/download/` URLs with no version resolution, and they work. Leave
  them alone.
- **`.github/workflows/docker-build.yml:28** (`password: ${{ secrets.GITHUB_TOKEN }}`)
  — this is the *correct* use of the token, for registry login. It must stay.
  Do not remove it. Only the `build-args` block goes.
- The `jq` entry in the apt install list (`Dockerfile:12`) — `jq` is no longer
  needed *by the build* after this change, but it is a user-facing tool that the
  README advertises. Keep it installed.
- `compose.yaml`, `README.md`, `config/yazi/**` — other plans own these.
- Digest-pinning the base image or adding checksum verification to the
  downloads. That is a real and separate concern, deliberately deferred.

## Git workflow

- Branch: `advisor/002-remove-token-build-arg`
- One commit is fine; message style is lowercase imperative with no prefix,
  e.g. `resolve dua version from release redirect, drop GITHUB_TOKEN build-arg`
- Do NOT push or open a PR.

## Steps

### Step 1: Replace the `dua-cli` block in the Dockerfile

Replace `Dockerfile` lines 41–51 (the comment, the `ARG`, and the `RUN`, exactly
as quoted in "Current state") with:

```dockerfile
# dua-cli — version resolved from the release redirect; needs no auth
RUN DUA_VERSION=$(curl -sILo /dev/null -w '%{url_effective}' \
        https://github.com/Byron/dua-cli/releases/latest \
        | sed 's#.*/tag/v##') \
    && [ -n "$DUA_VERSION" ] \
    && wget -qO /tmp/dua.tar.gz \
        "https://github.com/Byron/dua-cli/releases/latest/download/dua-v${DUA_VERSION}-x86_64-unknown-linux-musl.tar.gz" \
    && tar xzf /tmp/dua.tar.gz -C /tmp \
    && find /tmp -name dua -type f -exec mv {} /usr/local/bin/ \; \
    && rm -rf /tmp/dua*
```

What changed and why — do not "tidy" any of it away:

- The `ARG GITHUB_TOKEN=""` line is **deleted entirely**. This is the whole
  point of the plan.
- `curl -sILo /dev/null -w '%{url_effective}'` fetches headers only (`-I`),
  follows redirects (`-L`), discards the body, and prints the final URL.
- `sed 's#.*/tag/v##'` strips through `/tag/v`, leaving e.g. `2.41.1`.
  It uses `#` as the delimiter because the pattern contains `/`.
- `[ -n "$DUA_VERSION" ]` fails the build loudly if resolution ever returns
  empty, instead of silently constructing a 404 URL.
- The `wget`, `tar`, `find`, and `rm` lines are **unchanged** from the original.

**Verify** — run the exact resolution logic on the host:

```bash
DUA_VERSION=$(curl -sILo /dev/null -w '%{url_effective}' \
    https://github.com/Byron/dua-cli/releases/latest | sed 's#.*/tag/v##')
echo "resolved: $DUA_VERSION"
curl -sIo /dev/null -w 'asset: %{http_code}\n' -L \
    "https://github.com/Byron/dua-cli/releases/latest/download/dua-v${DUA_VERSION}-x86_64-unknown-linux-musl.tar.gz"
```

→ prints a bare semver like `resolved: 2.41.1` (no leading `v`, no URL
fragments) and `asset: 200`.

**If this machine has no network access**, this check cannot run. In that case:
make the edit anyway, and state plainly in your report that Step 1's
verification was **SKIPPED — no network**. Do not substitute a different
verification and do not claim it passed.

**Verify no ARG remains**: `grep -n 'ARG' Dockerfile` → returns nothing.

### Step 2: Remove the `build-args` input from the workflow

In `.github/workflows/docker-build.yml`, delete these two lines (36–37):

```yaml
          build-args: |
            GITHUB_TOKEN=${{ secrets.GITHUB_TOKEN }}
```

The `Build and push` step should end at the `tags:` line. Leave every other
line of the file untouched — in particular the `password: ${{ secrets.GITHUB_TOKEN }}`
on line 28 stays exactly as it is.

**Verify**: `python3 -c "import yaml; d=yaml.safe_load(open('.github/workflows/docker-build.yml')); s=[x for x in d['jobs']['build']['steps'] if x.get('name')=='Build and push'][0]; assert 'build-args' not in s['with'], s['with']; assert set(s['with'])=={'context','push','tags'}, set(s['with']); print('WORKFLOW OK')"`
→ prints `WORKFLOW OK`

**Verify the login step survived**: `grep -c 'secrets.GITHUB_TOKEN' .github/workflows/docker-build.yml`
→ prints `1`

### Step 3: Confirm the token is gone from the build path

**Verify**: `grep -n 'GITHUB_TOKEN' Dockerfile` → returns nothing (exit 1).

**Verify**: `grep -n 'api.github.com' Dockerfile` → returns nothing (exit 1).

## Test plan

This repo has no test suite and no test framework, and adding one is out of
scope here (a separate plan covers a CI smoke test). Verification for this plan
is:

1. **Behavioural** — Step 1 executes the real version-resolution pipeline
   against the live GitHub endpoint and confirms the constructed asset URL
   returns HTTP 200. This is the substantive check: it proves the replacement
   logic produces a working download URL.
2. **Structural** — Step 2 parses the workflow YAML and asserts the `with:` keys
   are exactly `{context, push, tags}`, which fails if `build-args` survives in
   any form.
3. **Negative** — Step 3 greps prove no `GITHUB_TOKEN` or API reference remains
   in the Dockerfile.

Do **not** add a test framework, a `package.json`, or a new CI job.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `grep -c GITHUB_TOKEN Dockerfile` returns 0 matches (exit 1)
- [ ] `grep -c 'api.github.com' Dockerfile` returns 0 matches (exit 1)
- [ ] `grep -c 'ARG' Dockerfile` returns 0 matches (exit 1)
- [ ] `grep -c 'secrets.GITHUB_TOKEN' .github/workflows/docker-build.yml` prints `1`
- [ ] `grep -c 'build-args' .github/workflows/docker-build.yml` returns 0 matches
- [ ] The workflow YAML parses and the `Build and push` step's `with:` keys are
      exactly `context`, `push`, `tags`
- [ ] The host-side resolution check prints a bare semver and `asset: 200`
      (or is explicitly reported as SKIPPED for lack of network)
- [ ] `git status --porcelain` shows changes only to `Dockerfile` and
      `.github/workflows/docker-build.yml`. No other path appears.

## STOP conditions

Stop and report back (do not improvise) if:

- The `Dockerfile` `dua-cli` block does not match the "Current state" excerpt
  — the repo has drifted and your replacement may discard someone's fix.
- The resolution check returns something that is not a bare semver — e.g. it
  still contains `https://` or `/tag/`, meaning the redirect shape changed. Do
  not hand-edit the `sed` pattern to compensate; report what the redirect
  actually returned.
- The asset URL check returns anything other than `200` — the release asset
  naming convention has changed and the whole approach needs revisiting.
- `.github/workflows/docker-build.yml` has more than one `secrets.GITHUB_TOKEN`
  reference after your edit, or zero.
- You conclude the fix requires touching the `eza` or `yazi` blocks. It does
  not; if you believe otherwise, stop and explain.

## Maintenance notes

For whoever owns this next:

- **The redirect is now a build dependency.** If GitHub ever changes the
  `/releases/latest` redirect target shape (currently `.../releases/tag/vX.Y.Z`),
  the `sed` pattern breaks. The `[ -n "$DUA_VERSION" ]` guard makes that a loud
  build failure rather than a silent 404, which is the intended behavior.
- **This same technique is needed by plan 003**, which installs `glow` from a
  GitHub release whose asset name also embeds the version. The two changes touch
  different, non-adjacent regions of the Dockerfile, so they should merge
  cleanly — but if you are reviewing both at once, check that they use a
  consistent resolution idiom rather than two different ones.
- **A reviewer should scrutinize** that line 28's `password: ${{ secrets.GITHUB_TOKEN }}`
  survived. Removing it would break registry login entirely — it is the correct
  and necessary use of the token.
- **Deliberately deferred**: this plan does not add checksum or signature
  verification to any of the three release downloads, and does not digest-pin
  `ubuntu:24.04`. Those are real supply-chain gaps tracked as a separate finding;
  bundling them here would have widened a small security fix into a risky one.
- **Rotation**: no rotation is required. The exposed credential was an ephemeral
  Actions `GITHUB_TOKEN`, automatically revoked at the end of each job, so every
  previously-exposed value is already dead. Past image layers still contain those
  dead strings; rebuilding `:latest` after this lands replaces them.
