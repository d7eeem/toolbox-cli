# Plan 003: Make the baked-in yazi config valid, and match it to what the image actually installs

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 09b4054..HEAD -- config/yazi Dockerfile README.md`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: LOW
- **Depends on**: none (see "Merge note" below regarding plan 002)
- **Category**: bug
- **Planned at**: commit `09b4054`, 2026-08-05

**Merge note**: plan 002 also edits `Dockerfile`, in the `dua-cli` block around
lines 41–51. This plan adds a *new* block after line 58. The two regions are not
adjacent and should merge cleanly, but be aware the file has another pending
change.

## Why this matters

The yazi config baked into this image is broken in three independent ways, all
silent — nothing errors, features just don't work:

1. **A TOML structure bug silently discards ~28 lines of settings.** Line 121
   opens a `[[manager.prepend_keymap]]` table, so every key after it —
   `cd_title` through `shell_offset` — becomes part of that keymap entry instead
   of the `[input]` section they were written for. All of the input-popup
   titles, positions and sizes are ignored. Compounding it, `manager` is the
   pre-25.5 spelling (it is `mgr` now) and yazi reads keybindings **only** from
   `keymap.toml`, never from `yazi.toml` — so the `g i` → lazygit binding there
   is dead twice over. Commit `ea4ec39 fix yazi breaking changes` renamed
   `manager` → `mgr` in `keymap.toml` but missed this file.

2. **The config calls programs the image does not install.** `glow` is set as
   the markdown previewer but is not installed, so every `.md` preview silently
   falls back to plain text. `lazygit` is not installed. The openers reference
   `player.sh`, `loupe`, and `imv-dir` — GUI programs that cannot work in a
   headless container even if they were installed, so opening an image or video
   does nothing at all.

3. **Host-machine paths leaked into the container config.** `keymap.toml:102`
   hardcodes `/home/tinker/.local/bin/omarchy/bg-next` — an absolute path for a
   different username, in a container whose `HOME` is `/root`. Line 101 calls
   `upload.sh`, which does not exist either.

Alongside these, three cheap cleanups ride along: duplicate keybindings where
one of each pair is dead, a stale duplicate plugin directory, and a malformed
`full-border` setup call.

When this lands, the config does what it says: markdown previews render,
media files show useful information, and no binding points at something that
isn't there.

## Decisions already made — do not re-litigate

These were decided by the repo owner. Implement exactly this:

- **Install `glow` only.** Markdown preview is the feature that degrades every
  time you hover a `.md` file, so `glow` gets installed. **`lazygit` does NOT
  get installed** — it is a larger binary and plain `git` is already present —
  so its keybinding and its vendored plugin are removed instead.
- **`mdcat` is removed.** It is vendored and declared as a dependency but wired
  to no previewer, so it is pure dead weight.
- **GUI openers become terminal-appropriate.** `loupe`, `imv-dir` and
  `player.sh` can never work in a headless container. Images map to `exiftool`
  and audio/video map to `mediainfo` — both already installed.

## Current state

Files involved, each with its role:

- `config/yazi/yazi.toml` — main config; contains the TOML structure bug
  (line 121) and the dangling openers/previewer.
- `config/yazi/keymap.toml` — keybindings; contains the duplicates and the
  host-machine paths.
- `config/yazi/init.lua` — 7 lines; plugin setup, contains the malformed
  `full-border` call.
- `config/yazi/package.toml` — declares vendored plugin/flavor dependencies.
- `config/yazi/plugins/` — vendored plugins, one directory each.
- `config/yazi/smart-enter_1.yazi/` — a stale duplicate of
  `plugins/smart-enter.yazi`, sitting outside `plugins/` so yazi never loads it.
- `Dockerfile` — installs tools; needs a `glow` block.
- `README.md` — line 9 lists the "Text & search" tools.

### The TOML structure bug

`config/yazi/yazi.toml:118-153` as it exists today (abridged in the middle, but
the shape is what matters):

```toml
[input]
cursor_blink = false

[[manager.prepend_keymap]]
on = ["g", "i"]
run = "plugin lazygit"
desc = "run lazygit"

# cd
cd_title = "Change directory:"
cd_origin = "top-center"
cd_offset = [0, 2, 50, 3]
# create
create_title = ["Create:", "Create (dir):"]
...
# shell
shell_title = ["Shell:", "Shell (block):"]
shell_origin = "top-center"
shell_offset = [0, 2, 50, 3]
```

Proof it is broken — parsing the file today shows `[input]` holds only one key,
and everything else landed inside the keymap entry:

```
$ python3 -c "import tomllib;d=tomllib.load(open('config/yazi/yazi.toml','rb'));print(list(d.keys()));print(d['input'])"
['mgr', 'preview', 'tasks', 'opener', 'open', 'plugin', 'input', 'manager', 'confirm', 'pick', 'which']
{'cursor_blink': False}
```

Note `'manager'` present as a top-level key — that is the bug — and `input`
containing only `cursor_blink`.

### The openers and open rules

`config/yazi/yazi.toml:36-52` as it exists today:

```toml
[opener]
play = [
  { run = 'player.sh "$@"', orphan = true, for = "unix" },
  { run = '"C:\Program Files\mpv.exe" %*', orphan = true, for = "windows" },
]
edit = [
  { run = '${EDITOR:=nvim} "$@"', desc = "$EDITOR", block = true, for = "unix" },
  { run = 'nvim "%*"', desc = "$EDITOR", block = true, for = "windows" },
]
extract = [
  { run = '7zfm "%1"', desc = "Open in 7zfm", orphan = true, for = "windows" },
  { run = 'ya pub extract --list "$@"', desc = "Extract here", for = "unix" },
  { run = 'ya pub extract --list %*', desc = "Extract here", for = "windows" },
]
view = [
  { run = 'loupe "$@" || imv-dir "$@"', desc = "$EDITOR", block = true, for = "unix" },
]
```

The `for = "windows"` entries are dead weight in a Linux-only image (the base is
`ubuntu:24.04` and all three downloaded binaries are `x86_64` Linux), and are
removed as part of this rewrite.

### The keymap duplicates

Verified by parsing `config/yazi/keymap.toml` today:

```
duplicate bindings in [mgr].keymap:
  n x 2
  N x 2
  l x 2
prepend: [{'on': 'l', 'run': 'plugin smart-enter'}]
```

The specific lines:

- `keymap.toml:19-20` — `n` → `touch`, `N` → `mkdir`
- `keymap.toml:154-155` — `n` → `find_arrow`, `N` → `find_arrow --previous`
- `keymap.toml:45-47` — `l` → `enter` immediately followed by `l` → `open`
- `keymap.toml:94-95` — `.` → `hidden toggle` and `z` → `hidden toggle`
  (identical); the `z` → zoxide binding it was presumably meant for is commented
  out at line 99, and zoxide is not installed.

### The host paths

`config/yazi/keymap.toml:101-102` as they exist today:

```toml
  { on = "u", run = "shell --block --confirm 'upload.sh \"$@\"'", desc = "Upload selected files" },
  { on = "b", run = "shell --block --confirm '/home/tinker/.local/bin/omarchy/bg-next \"$@\"'", desc = "bg-next"},
```

### The malformed full-border call

`config/yazi/init.lua` in full, as it exists today (all 7 lines):

```lua
require("full-border"):setup {
  typr = ui.Border, ROUNDED,
}
require("git"):setup()
require("smart-enter"):setup {
  open_multi = true,
}
```

`typr` is a typo for `type`, and bare `ROUNDED` is an undefined global (it should
be `ui.Border.ROUNDED`), so it evaluates to `nil` and contributes nothing. The
plugin's own code at `config/yazi/plugins/full-border.yazi/main.lua:4` reads
`opts.type` and falls back to `ui.Border.ROUNDED`:

```lua
local type = opts and opts.type or ui.Border.ROUNDED
```

So the border currently renders correctly **by accident**. This is a
correctness-of-intent fix, not a visible bug fix — the rendered output should be
identical before and after.

### The Dockerfile install pattern to match

`config/yazi/` aside, the `Dockerfile` installs three tools from GitHub releases.
The `yazi` block at lines 53–58 as it exists today:

```dockerfile
# yazi
RUN curl -Lo /tmp/yazi.zip \
        https://github.com/sxyazi/yazi/releases/latest/download/yazi-x86_64-unknown-linux-musl.zip \
    && unzip /tmp/yazi.zip -d /tmp/yazi \
    && mv /tmp/yazi/yazi*/yazi /usr/local/bin/ \
    && rm -rf /tmp/yazi*
```

Single `RUN`, `&&`-chained, 4-space continuation indent, `rm -rf /tmp/<name>*`
cleanup last. Match that shape.

**Verified facts about the glow release** — these commands were run against live
GitHub while writing this plan:

```
$ curl -sILo /dev/null -w '%{url_effective}\n' https://github.com/charmbracelet/glow/releases/latest
https://github.com/charmbracelet/glow/releases/tag/v2.1.2

$ curl -sIo /dev/null -w '%{http_code}' -L "https://github.com/charmbracelet/glow/releases/latest/download/glow_2.1.2_Linux_x86_64.tar.gz"
200
```

Note the asset name embeds the version **without** a `v` prefix and uses
`_Linux_x86_64`, unlike the musl-style names used by eza/dua/yazi.

### Repo conventions

No application code, no linter, no test suite. TOML in `config/yazi/` uses
2-space indent for inline-table array entries. Commit messages are plain
lowercase imperative, no conventional-commit prefix; real examples from
`git log`:

```
fix yazi breaking changes
remove GitHub API calls from build, use direct /latest/download/ URLs instead
add Dependabot for auto-updating GitHub Actions
```

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Parse yazi.toml | `python3 -c "import tomllib; tomllib.load(open('config/yazi/yazi.toml','rb')); print('OK')"` | prints `OK` |
| Parse keymap.toml | `python3 -c "import tomllib; tomllib.load(open('config/yazi/keymap.toml','rb')); print('OK')"` | prints `OK` |
| Parse package.toml | `python3 -c "import tomllib; tomllib.load(open('config/yazi/package.toml','rb')); print('OK')"` | prints `OK` |
| Grep audit | `grep -rn '<pattern>' config/` | as specified per step |

This repo has no build, test, lint, or typecheck command. `tomllib` parsing plus
targeted assertions is the verification gate. Do **not** run `docker build` —
this image installs the full ffmpeg and imagemagick suites and takes many
minutes.

If a Lua interpreter happens to be available (`command -v luac || command -v lua`),
running `luac -p config/yazi/init.lua` is a useful extra syntax check. If not
available, skip it — it is not required.

## Scope

**In scope** (the only paths you may modify, create, or delete):

- `config/yazi/yazi.toml` (modify)
- `config/yazi/keymap.toml` (modify)
- `config/yazi/init.lua` (modify)
- `config/yazi/package.toml` (modify)
- `config/yazi/plugins/mdcat.yazi/` (delete the whole directory)
- `config/yazi/plugins/lazygit.yazi/` (delete the whole directory)
- `config/yazi/smart-enter_1.yazi/` (delete the whole directory)
- `Dockerfile` (add one new `RUN` block only — see Step 6)
- `README.md` (**line 9 only** — the "Text & search" bullet)

**Out of scope** (do NOT touch, even though they look related):

- **The `url = "*"` / `url = "*.md"` keys in `[plugin] prepend_previewers` and
  `[[plugin.prepend_fetchers]]` (`yazi.toml:104-116`).** The vendored plugin
  READMEs (`plugins/git.yazi/README.md`, `plugins/glow.yazi/README.md`) show
  `name = "*"` instead. **Those READMEs are stale.** Current yazi documentation
  uses `url`, which is what this repo already has. Changing `url` to `name` would
  silently break the git fetcher and the markdown previewer. Leave these keys
  exactly as they are.
- The two `[[plugin.prepend_fetchers]]` entries both using `id = "git"` — this
  duplication is the documented, correct setup (one rule for files, one for
  directories). Not a bug.
- `config/yazi/theme.toml`, `config/yazi/flavors/**` — the flavor selection and
  both vendored flavors are fine.
- `config/yazi/plugins/full-border.yazi/`, `plugins/git.yazi/`,
  `plugins/smart-enter.yazi/`, `plugins/glow.yazi/` — these are vendored
  upstream code that stays. Do not edit files inside them; only `init.lua`'s
  *call into* full-border changes.
- The `dua-cli` block in `Dockerfile` (lines 41–51) — plan 002 owns it.
- `README.md` lines 13 onward — plan 001 owns the quick-start, building, and
  configuration sections. Touch only line 9.
- `compose.yaml`, `.github/workflows/**`, `.env`, `.gitignore`.

## Git workflow

- Branch: `advisor/003-fix-yazi-config`
- Commit per logical step is fine, or one commit for the whole plan; message
  style is lowercase imperative with no prefix, e.g.
  `fix yazi.toml input section, install glow, drop dangling config`
- Do NOT push or open a PR.
- Use `git rm -r` for the directory deletions so they are staged properly.

## Steps

### Step 1: Fix the `[input]` section and delete the dead keymap block

In `config/yazi/yazi.toml`, replace everything from line 118 (`[input]`) through
line 153 (`shell_offset = [0, 2, 50, 3]`) with the block below. The only real
changes are: the `[[manager.prepend_keymap]]` table (4 lines including its
comment-free body) is **deleted entirely**, and the settings that followed it now
sit directly under `[input]` where they belong.

```toml
[input]
cursor_blink = false
# cd
cd_title = "Change directory:"
cd_origin = "top-center"
cd_offset = [0, 2, 50, 3]
# create
create_title = ["Create:", "Create (dir):"]
create_origin = "top-center"
create_offset = [0, 2, 50, 3]
# rename
rename_title = "Rename:"
rename_origin = "hovered"
rename_offset = [0, 1, 50, 3]
# filter
filter_title = "Filter:"
filter_origin = "top-center"
filter_offset = [0, 2, 50, 3]
# find
find_title = ["Find next:", "Find previous:"]
find_origin = "top-center"
find_offset = [0, 2, 50, 3]
# search
search_title = "Search via {n}:"
search_origin = "top-center"
search_offset = [0, 2, 50, 3]
# shell
shell_title = ["Shell:", "Shell (block):"]
shell_origin = "top-center"
shell_offset = [0, 2, 50, 3]
```

The `g i` → lazygit binding is gone on purpose: lazygit is not being installed,
and keybindings do not belong in `yazi.toml` regardless.

**Verify**: `python3 -c "import tomllib; d=tomllib.load(open('config/yazi/yazi.toml','rb')); assert 'manager' not in d, 'manager key still present'; i=d['input']; assert i['cursor_blink'] is False; assert i['cd_title']=='Change directory:'; assert i['shell_offset']==[0,2,50,3]; assert i['rename_origin']=='hovered'; assert len(i)==22, len(i); print('INPUT SECTION OK')"`
→ prints `INPUT SECTION OK`

### Step 2: Replace the openers and the image/video open rules

In `config/yazi/yazi.toml`, replace the whole `[opener]` section (lines 36–52,
quoted in "Current state") with:

```toml
[opener]
edit = [
  { run = '${EDITOR:=nvim} "$@"', desc = "$EDITOR", block = true, for = "unix" },
]
info = [
  { run = 'mediainfo "$@" | less -R', desc = "Media info", block = true, for = "unix" },
]
exif = [
  { run = 'exiftool "$@" | less -R', desc = "EXIF metadata", block = true, for = "unix" },
]
extract = [
  { run = 'ya pub extract --list "$@"', desc = "Extract here", for = "unix" },
]
```

Then in the `[open]` `rules` array (lines 54–101), make exactly these changes:

- **Delete** the first rule entirely — `{ url = "*.m3u", use = ["play", "edit", "reveal"] }`.
  `play` no longer exists; `.m3u` is plain text and the `text/*` rule covers it.
- Change the `image/*` rule's `use` from `["view"]` to `["exif", "edit", "reveal"]`.
- Change the `{audio,video}/*` rule's `use` from `["play", "reveal"]` to
  `["info", "reveal"]`.
- Leave every other rule exactly as it is.

`mediainfo`, `exiftool`, and `less` are all already installed by
`Dockerfile:5-32`; verify that for yourself in Step 6's check.

**Verify**: `python3 -c "import tomllib; d=tomllib.load(open('config/yazi/yazi.toml','rb')); o=d['opener']; assert set(o)=={'edit','info','exif','extract'}, set(o); assert all(e.get('for')=='unix' for v in o.values() for e in v), 'windows entry left behind'; r=d['open']['rules']; assert not any(x.get('url')=='*.m3u' for x in r), 'm3u rule still present'; img=[x for x in r if x.get('mime')=='image/*'][0]; assert img['use']==['exif','edit','reveal'], img['use']; av=[x for x in r if x.get('mime')=='{audio,video}/*'][0]; assert av['use']==['info','reveal'], av['use']; print('OPENERS OK')"`
→ prints `OPENERS OK`

**Verify nothing dangling remains**: `grep -nE 'player\.sh|loupe|imv-dir|7zfm|mpv\.exe' config/yazi/yazi.toml`
→ returns nothing (exit 1)

### Step 3: Remove the duplicate and host-specific keybindings

In `config/yazi/keymap.toml`, delete exactly these five lines:

1. Line 19 — `{ on = "n", run = "touch", desc = "Create file" },`
2. Line 20 — `{ on = "N", run = "mkdir", desc = "Create directory" },`
3. Line 47 — `{ on = "l", run = "open", desc = "Open selected files" },`
4. Line 95 — `{ on = "z", run = "hidden toggle", desc = "Toggle the visibility of hidden files" },`
5. Lines 101–102 — the `upload.sh` and `/home/tinker/...bg-next` bindings (both lines)

Keep these, which are **not** duplicates and must survive:

- Line 18 `<C-n>` → `mkdir`
- Line 45 `l` → `enter` (the prepended `plugin smart-enter` overrides it at
  runtime, but the default stays as the documented fallback)
- Line 90 `a` → `create` (this is how files/dirs get created; it is why the
  `n`/`N` create bindings are the ones to drop)
- Line 94 `.` → `hidden toggle`
- Lines 154–155 `n` / `N` → `find_arrow` (restores yazi's standard behavior)

**Verify**: `python3 -c "
import tomllib
from collections import Counter
d=tomllib.load(open('config/yazi/keymap.toml','rb'))
km=d['mgr']['keymap']
c=Counter(e['on'] if isinstance(e['on'],str) else tuple(e['on']) for e in km)
dups={k:v for k,v in c.items() if v>1}
assert not dups, dups
by={ (e['on'] if isinstance(e['on'],str) else tuple(e['on'])):e['run'] for e in km }
assert by['n']=='find_arrow', by['n']
assert by['N']=='find_arrow --previous', by['N']
assert by['l']=='enter', by['l']
assert by['<C-n>']=='mkdir'
assert by['.']=='hidden toggle'
assert 'z' not in by
assert 'u' not in by and 'b' not in by
print('KEYMAP OK')"`
→ prints `KEYMAP OK`

**Verify no host paths remain anywhere**: `grep -rn '/home/tinker\|upload\.sh' config/`
→ returns nothing (exit 1)

### Step 4: Fix the `full-border` setup call

Replace the first three lines of `config/yazi/init.lua` so the whole file reads:

```lua
require("full-border"):setup {
  type = ui.Border.ROUNDED,
}
require("git"):setup()
require("smart-enter"):setup {
  open_multi = true,
}
```

Only line 2 changes (`typr = ui.Border, ROUNDED,` → `type = ui.Border.ROUNDED,`).
Leave the `git` and `smart-enter` setup calls untouched.

**Verify**: `grep -q 'type = ui.Border.ROUNDED' config/yazi/init.lua && ! grep -q 'typr' config/yazi/init.lua && echo INIT_OK`
→ prints `INIT_OK`

### Step 5: Drop the dead plugins and the stale duplicate directory

In `config/yazi/package.toml`, delete the two `[[plugin.deps]]` entries whose
`use` values are `GrzegorzKozub/mdcat` (lines 17–19) and `Lil-Dank/lazygit`
(lines 26–29), along with their `rev` and `hash` lines. Keep the `glow`,
`smart-enter`, `full-border`, and `git` plugin deps, and keep both
`[[flavor.deps]]` entries.

Then delete these three directories:

```bash
git rm -r config/yazi/plugins/mdcat.yazi
git rm -r config/yazi/plugins/lazygit.yazi
git rm -r config/yazi/smart-enter_1.yazi
```

`smart-enter_1.yazi` is a stale duplicate of `plugins/smart-enter.yazi`: it sits
outside `plugins/` so yazi never loads it, and it calls the removed
`ya.manager_emit` API. Deleting it removes a trap for the next reader.

**Verify**: `python3 -c "import tomllib; d=tomllib.load(open('config/yazi/package.toml','rb')); u=[x['use'] for x in d['plugin']['deps']]; assert sorted(u)==['Reledia/glow','yazi-rs/plugins:full-border','yazi-rs/plugins:git','yazi-rs/plugins:smart-enter'], u; assert len(d['flavor']['deps'])==2; print('PACKAGE OK')"`
→ prints `PACKAGE OK`

**Verify the directories are gone**: `test ! -e config/yazi/plugins/mdcat.yazi && test ! -e config/yazi/plugins/lazygit.yazi && test ! -e config/yazi/smart-enter_1.yazi && echo DIRS_REMOVED_OK`
→ prints `DIRS_REMOVED_OK`

**Verify no reference survives**: `grep -rn 'mdcat\|lazygit' config/ Dockerfile`
→ returns nothing (exit 1)

### Step 6: Install `glow` in the Dockerfile

In `Dockerfile`, insert a new block immediately after the `yazi` block (which
ends at line 58 with `&& rm -rf /tmp/yazi*`) and before the `# Aliases` comment
on line 60:

```dockerfile
# glow — markdown renderer used by yazi's glow previewer
RUN GLOW_VERSION=$(curl -sILo /dev/null -w '%{url_effective}' \
        https://github.com/charmbracelet/glow/releases/latest \
        | sed 's#.*/tag/v##') \
    && [ -n "$GLOW_VERSION" ] \
    && wget -qO /tmp/glow.tar.gz \
        "https://github.com/charmbracelet/glow/releases/latest/download/glow_${GLOW_VERSION}_Linux_x86_64.tar.gz" \
    && tar xzf /tmp/glow.tar.gz -C /tmp \
    && find /tmp -name glow -type f -exec mv {} /usr/local/bin/ \; \
    && rm -rf /tmp/glow*
```

Points that matter — do not "simplify" them:

- The asset name uses the version **without** a leading `v`, hence the
  `sed 's#.*/tag/v##'` which strips it.
- It is `_Linux_x86_64.tar.gz`, not the `-x86_64-unknown-linux-musl` form the
  other three tools use.
- `[ -n "$GLOW_VERSION" ]` fails the build loudly rather than constructing a 404
  URL silently.
- No `ARG` and no GitHub API call — this needs no authentication.

**Verify** — run the resolution logic on the host:

```bash
GLOW_VERSION=$(curl -sILo /dev/null -w '%{url_effective}' \
    https://github.com/charmbracelet/glow/releases/latest | sed 's#.*/tag/v##')
echo "resolved: $GLOW_VERSION"
curl -sIo /dev/null -w 'asset: %{http_code}\n' -L \
    "https://github.com/charmbracelet/glow/releases/latest/download/glow_${GLOW_VERSION}_Linux_x86_64.tar.gz"
```

→ prints a bare semver like `resolved: 2.1.2` and `asset: 200`.

**If this machine has no network access**, make the edit anyway and report Step 6's
verification as **SKIPPED — no network**. Do not substitute a different check and
do not claim it passed.

**Verify the openers' dependencies are genuinely installed**: `grep -cE '^\s+(mediainfo|exiftool|less)\s*\\$' Dockerfile`
→ prints `3`

### Step 7: Add `glow` to the README tool list

In `README.md`, change **line 9 only**, from:

```markdown
- **Text & search**: neovim, ripgrep, bat, jq, fzf, less
```

to:

```markdown
- **Text & search**: neovim, ripgrep, bat, jq, fzf, less, glow
```

Do not touch any other line of `README.md` — the quick-start, building, and
configuration sections belong to a different plan.

**Verify**: `grep -n 'glow' README.md`
→ prints exactly one line, number 9

## Test plan

This repo has no test suite and no test framework, and adding one is out of
scope here (a separate plan covers a CI smoke test that would run the built
image). Verification for this plan is structural and behavioural rather than
unit tests:

1. **Structural (the substantive check for findings C, E, F)** — Steps 1, 2, 3
   and 5 parse the actual TOML with `tomllib` and assert on the resulting data
   structure, not on text. The Step 1 assertion `'manager' not in d` and
   `len(i)==22` is precisely the bug this plan exists to fix: it fails on the
   current file and passes only when the settings really land under `[input]`.
   The Step 3 duplicate-detection assertion likewise fails on the current file.
2. **Behavioural (finding D)** — Step 6 executes the real glow version-resolution
   pipeline against live GitHub and confirms the constructed asset URL returns
   HTTP 200.
3. **Negative** — greps prove no reference to `player.sh`, `loupe`, `imv-dir`,
   `mdcat`, `lazygit`, `upload.sh`, or `/home/tinker` survives anywhere under
   `config/` or in the `Dockerfile`.

Do **not** add a test framework, a `package.json`, or a new CI job.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] All three TOML files parse: `yazi.toml`, `keymap.toml`, `package.toml`
- [ ] `python3 -c "import tomllib; d=tomllib.load(open('config/yazi/yazi.toml','rb')); assert 'manager' not in d; assert len(d['input'])==22; print('OK')"` prints `OK`
- [ ] `yazi.toml` `[opener]` keys are exactly `{edit, info, exif, extract}` and
      every entry has `for = "unix"`
- [ ] `image/*` rule uses `["exif","edit","reveal"]`; `{audio,video}/*` uses
      `["info","reveal"]`; no `*.m3u` rule remains
- [ ] `keymap.toml` `[mgr].keymap` has **zero** duplicate `on` values
- [ ] `n` → `find_arrow`, `N` → `find_arrow --previous`, `l` → `enter`,
      `<C-n>` → `mkdir`, `.` → `hidden toggle`; no `z`, `u`, or `b` binding
- [ ] `grep -rn '/home/tinker\|upload\.sh' config/` returns nothing
- [ ] `grep -rn 'mdcat\|lazygit' config/ Dockerfile` returns nothing
- [ ] `grep -nE 'player\.sh|loupe|imv-dir|7zfm|mpv\.exe' config/yazi/yazi.toml` returns nothing
- [ ] `config/yazi/init.lua` contains `type = ui.Border.ROUNDED` and not `typr`
- [ ] `config/yazi/plugins/mdcat.yazi`, `config/yazi/plugins/lazygit.yazi`, and
      `config/yazi/smart-enter_1.yazi` do not exist
- [ ] `package.toml` plugin deps are exactly glow, full-border, git,
      smart-enter; both flavor deps intact
- [ ] `Dockerfile` contains a `glow` RUN block; glow resolution prints a semver
      and `asset: 200` (or is explicitly reported SKIPPED for lack of network)
- [ ] `grep -c 'glow' README.md` prints `1`
- [ ] `git status --porcelain` shows changes only to: `config/yazi/yazi.toml`,
      `config/yazi/keymap.toml`, `config/yazi/init.lua`,
      `config/yazi/package.toml`, the three deleted directories, `Dockerfile`,
      `README.md`. No other path appears.

## STOP conditions

Stop and report back (do not improvise) if:

- Any "Current state" excerpt does not match the live file — particularly
  `yazi.toml:118-153` and `init.lua`. The repo has drifted and your replacement
  may discard someone's fix.
- After Step 1, `len(d['input'])` is anything other than 22. That means you
  dropped or duplicated a setting while moving the block; report the actual
  count and the key list rather than adjusting the assertion.
- The glow redirect returns something that is not a bare semver, or the asset
  URL returns anything other than `200`. The release naming has changed; do not
  hand-tune the URL — report what you actually observed.
- You find yourself wanting to change `url = ` to `name = ` anywhere in
  `yazi.toml`. Do not. Re-read the "Out of scope" note and stop if you still
  believe it is needed.
- Deleting `plugins/lazygit.yazi` or `plugins/mdcat.yazi` turns out to break a
  reference somewhere you did not expect (the greps in Step 5 should come back
  empty — if they do not, stop).
- A step's verification fails twice after a reasonable fix attempt.

## Maintenance notes

For whoever owns this next:

- **The `[input]` block is position-sensitive.** Everything from `cd_title`
  down belongs to `[input]`, and TOML bare keys attach to whatever table header
  most recently preceded them. If someone later adds a `[[mgr.prepend_keymap]]`
  or any other table header into the middle of `yazi.toml`, the same class of
  silent bug returns. The `len(d['input'])==22` assertion in the done criteria
  is the cheap regression check — worth keeping in any future CI smoke test.
- **Keybindings live in `keymap.toml` only.** yazi does not read them from
  `yazi.toml`, so anything keymap-shaped appearing there is dead on arrival.
- **The bundled plugin READMEs are stale about `name` vs `url`.** Anyone reading
  `plugins/git.yazi/README.md` or `plugins/glow.yazi/README.md` will be told to
  write `name = "*"`. Current yazi wants `url`. Expect this to come up again.
- **`glow` is now a build-time download whose asset name embeds the version.**
  If charmbracelet changes their release asset naming, the build fails loudly at
  the `wget` (by design). Plan 002 introduces the same redirect-resolution idiom
  for `dua-cli`; keep the two consistent if either is revised.
- **A reviewer should scrutinize**: that no setting was lost while relocating the
  `[input]` block (count the keys), that `url =` keys were left alone, and that
  the `image/*` opener change is acceptable — hitting Enter on a photo now shows
  EXIF metadata rather than attempting to display it, which is the only thing
  that can work in a headless container.
- **Deliberately deferred**: installing `lazygit` (decided against — plain `git`
  is present), adding the glow `<C-e>`/`<C-y>` scroll bindings its README
  suggests, and any change to image/video *preview* (as opposed to opening),
  which depends on terminal graphics protocol support outside this repo's
  control.
