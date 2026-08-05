# toolbox

A portable CLI toolbox Docker image based on Ubuntu 24.04, packed with common system administration and media processing tools.

## Included tools

- **Files & disk**: ncdu, dua-cli, eza, fd-find, file, 7zip, zstd, pigz, unzip, unrar
- **Media**: ffmpeg, ffmpegthumbnailer, mediainfo, exiftool, imagemagick
- **Text & search**: neovim, ripgrep, bat, jq, fzf, less, glow
- **System**: htop, tmux, curl, wget, git
- **Navigation**: yazi (terminal file manager)

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

## Deploying on TrueNAS SCALE

This image targets TrueNAS SCALE, an always-on storage appliance where you
can't install native packages and anything you did install wouldn't survive an
OS update. A persistent container you `docker exec` into is the durable way to
keep these tools around.

Two things differ from a desktop setup:

**Mount your datasets, not your home directory.** The default mount is the
host `$HOME`, which on a NAS is not where your data lives. Either set
`TOOLBOX_MOUNT` in `.env` to a pool path:

```bash
TOOLBOX_MOUNT=/mnt/tank
```

or uncomment and edit the per-dataset examples in `compose.yaml` for finer
control over what the container can reach. Pool and dataset names are specific
to your installation, so nothing is mounted by default.

**Files are created as root.** The container runs as root, so anything it
writes into a mounted dataset is owned by `root`. If that conflicts with how
other apps access those datasets, you will need to `chown` afterwards. Running
as a non-root user with a matching UID/GID is tracked as a separate change.

## Aliases (included in image)

- `cat` -> `batcat --paging=never`
- `bat` -> `batcat --paging=never`
- `ls` -> `eza --icons`
- `ll` -> `eza -la --icons`
- `la` -> `eza -a --icons`
- `fd` -> `fdfind`

## License

MIT
