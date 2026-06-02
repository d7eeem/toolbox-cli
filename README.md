# toolbox

A portable CLI toolbox Docker image based on Ubuntu 24.04, packed with common system administration and media processing tools.

## Included tools

- **Files & disk**: ncdu, dua-cli, eza, fd-find, file, 7zip, zstd, pigz, unzip, unrar
- **Media**: ffmpeg, ffmpegthumbnailer, mediainfo, exiftool, imagemagick
- **Text & search**: neovim, ripgrep, bat, jq, fzf, less
- **System**: htop, tmux, curl, wget, git
- **Navigation**: yazi (terminal file manager)

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

## Aliases (included in image)

- `cat` -> `batcat --paging=never`
- `bat` -> `batcat --paging=never`
- `ls` -> `eza --icons`
- `ll` -> `eza -la --icons`
- `la` -> `eza -a --icons`
- `fd` -> `fdfind`

## License

MIT
