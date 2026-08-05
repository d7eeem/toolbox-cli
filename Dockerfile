FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive

# Base tools + ffmpeg suite
RUN apt-get update && apt-get install -y \
    ncdu \
    curl \
    git \
    wget \
    unzip \
    unrar \
    jq \
    file \
    7zip \
    zstd \
    pigz \
    less \
    neovim \
    ffmpeg \
    ffmpegthumbnailer \
    mediainfo \
    exiftool \
    imagemagick \
    fzf \
    ripgrep \
    bat \
    fd-find \
    htop \
    tmux \
    openssh-client \
    # rsync \
    && rm -rf /var/lib/apt/lists/*

# eza
RUN wget -qO /tmp/eza.tar.gz \
        "https://github.com/eza-community/eza/releases/latest/download/eza_x86_64-unknown-linux-musl.tar.gz" \
    && tar xzf /tmp/eza.tar.gz -C /tmp \
    && mv /tmp/eza /usr/local/bin/ \
    && rm -rf /tmp/eza*

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

# yazi
RUN curl -Lo /tmp/yazi.zip \
        https://github.com/sxyazi/yazi/releases/latest/download/yazi-x86_64-unknown-linux-musl.zip \
    && unzip /tmp/yazi.zip -d /tmp/yazi \
    && mv /tmp/yazi/yazi*/yazi /tmp/yazi/yazi*/ya /usr/local/bin/ \
    && rm -rf /tmp/yazi*

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

# Aliases
RUN echo 'alias cat="batcat --paging=never"' >> /etc/bash.bashrc \
    && echo 'alias bat="batcat --paging=never"' >> /etc/bash.bashrc \
    && echo 'alias ls="eza --icons"'            >> /etc/bash.bashrc \
    && echo 'alias ll="eza -la --icons"'        >> /etc/bash.bashrc \
    && echo 'alias la="eza -a --icons"'         >> /etc/bash.bashrc \
    && echo 'alias fd="fdfind"'                 >> /etc/bash.bashrc

# LazyVim
RUN git clone https://github.com/LazyVim/starter ~/.config/nvim

# Config baked into image
COPY config/ /root/.config/

CMD ["sleep", "infinity"]
