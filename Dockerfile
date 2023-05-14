# syntax=docker/dockerfile:1.4

ARG BUILDPLATFORM=$BUILDPLATFORM
ARG BUILDOS=$BUILDOS
ARG BUILDARCH=$BUILDARCH
ARG BUILDVARIANT=$BUILDVARIANT

ARG TARGETPLATFORM=$TARGETPLATFORM
ARG TARGETOS=$TARGETOS
ARG TARGETARCH=$TARGETARCH
ARG TARGETVARIANT=$TARGETVARIANT

# -----------------------------------------------------------------------------
# PLATFORM STAGE: AMD64 (x86_64)
# -----------------------------------------------------------------------------
# hadolint ignore=DL3007
FROM --platform=linux/amd64 archlinux:latest AS bootstrap-archlinux-amd64

# Init keyring and update
RUN pacman-key --init && \
    pacman-key --populate archlinux

# Copy custom configs
# hadolint ignore=DL3021
COPY --link ./amd64/pacman.conf /etc/pacman.conf
# hadolint ignore=DL3021
COPY --link ./amd64/makepkg.conf /etc/makepkg.conf

# -----------------------------------------------------------------------------
# PLATFORM STAGE: ARM/v7 (armv7)
# -----------------------------------------------------------------------------
# hadolint ignore=DL3007
FROM --platform=$BUILDPLATFORM alpine:latest AS bootstrap0-archlinux-armv7

# Install curl bash and update CA certificates
# hadolint ignore=DL3018
RUN apk add --no-cache wget bash tar ca-certificates \
  && update-ca-certificates

RUN wget --progress=dot:giga --prefer-family=IPv4 \
        --user-agent="Mozilla/5.0 (X11; Fedora; Linux x86_64; rv:52.0) Gecko/20100101 Firefox/52.0" \
        http://os.archlinuxarm.org/os/ArchLinuxARM-armv7-latest.tar.gz && \
    mkdir -p /rootfs && \
    tar -v -C /rootfs --extract --file "ArchLinuxARM-armv7-latest.tar.gz"

FROM --platform=linux/arm/v7 scratch AS bootstrap-archlinux-armv7
COPY --from=bootstrap0-archlinux-armv7 /rootfs/ /

# hadolint ignore=DL3021
COPY --link ./generic/pacman.conf /etc/pacman.conf

# Init keyring and update
RUN pacman-key --init && \
    pacman-key --populate archlinuxarm

# Remove linux package
RUN pacman -Rscun linux-armv7 linux-firmware --noconfirm --noprogressbar

# Remove boot leftovers
# hadolint ignore=SC2115
RUN rm -rf /boot/*

# -----------------------------------------------------------------------------
# PLATFORM STAGE: ARM64/v8 (aarch64)
# -----------------------------------------------------------------------------
# hadolint ignore=DL3007
FROM --platform=$BUILDPLATFORM alpine:latest AS bootstrap0-archlinux-arm64

# Install curl bash and update CA certificates
# hadolint ignore=DL3018
RUN apk add --no-cache wget bash tar ca-certificates \
  && update-ca-certificates

RUN wget --progress=dot:giga --prefer-family=IPv4 \
        --user-agent="Mozilla/5.0 (X11; Fedora; Linux x86_64; rv:52.0) Gecko/20100101 Firefox/52.0" \
        http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz && \
    mkdir -p /rootfs && \
    tar -v -C /rootfs --extract --file "ArchLinuxARM-aarch64-latest.tar.gz"

FROM --platform=linux/arm64 scratch AS bootstrap-archlinux-arm64
COPY --from=bootstrap0-archlinux-arm64 /rootfs/ /

# hadolint ignore=DL3021
COPY --link ./generic/pacman.conf /etc/pacman.conf

# Init keyring and update
RUN pacman-key --init && \
    pacman-key --populate archlinuxarm

# Remove linux package
RUN pacman -Rscun linux-aarch64 linux-firmware --noconfirm --noprogressbar

# Remove boot leftovers
# hadolint ignore=SC2115
RUN rm -rf /boot/*

# -----------------------------------------------------------------------------
# BUILDER BOOTSTRAP
# -----------------------------------------------------------------------------
# hadolint ignore=DL3006
FROM --platform=$BUILDPLATFORM bootstrap-archlinux-${BUILDARCH}${BUILDVARIANT} AS bootstrap-archlinux-builder

# Update and install build tools
RUN pacman -Syyu base base-devel pacman-contrib devtools --noprogressbar --needed --noconfirm

# -----------------------------------------------------------------------------
# PLATFORM STAGE: i386 (x86) (After build platform bootstrap stage)
# -----------------------------------------------------------------------------
FROM --platform=$BUILDPLATFORM bootstrap-archlinux-builder AS bootstrap0-archlinux-386

ENV PACMAN_MIRRORLIST 'Server = https://mirror.archlinux32.org/$arch/$repo'

# hadolint ignore=DL3021
COPY --link ./generic/pacman-nosig.conf /etc/pacman.conf
RUN echo "$PACMAN_MIRRORLIST" > /etc/pacman.d/mirrorlist

# hadolint ignore=SC3009
RUN --network=none mkdir -p /rootfs/ && \
                   mkdir -m 0755 -p /rootfs/var/{cache/pacman/pkg,lib/pacman,log} /rootfs/{dev,run,etc} && \
                   mkdir -m 1777 -p /rootfs/tmp && \
                   mkdir -m 0555 -p /rootfs/{sys,proc} && \
                   mknod /rootfs/dev/null c 1 3

RUN pacman -r /rootfs/ --arch i686 -Sy --noconfirm --noprogressbar base archlinux32-keyring

COPY --link ./i686/pacman.conf /rootfs/etc/pacman.conf
RUN echo "$PACMAN_MIRRORLIST" > /rootfs/etc/pacman.d/mirrorlist

FROM --platform=linux/386 scratch AS bootstrap-archlinux-386
COPY --from=bootstrap0-archlinux-386 /rootfs/ /

# Init keyring and update
RUN pacman-key --init && \
    curl -Ss 'https://archlinux32.org/keys.php?k=5FDCA472AB93292BC678FD59255A76DB9A12601A' | gpg --homedir /etc/pacman.d/gnupg/ --import && \
    curl -Ss 'https://archlinux32.org/keys.php?k=16194A82231E9EF823562181C8E8F5A0AF9BA7E7' | gpg --homedir /etc/pacman.d/gnupg/ --import && \
    pacman-key --populate && \
    pacman-key --refresh

# -----------------------------------------------------------------------------
# BOOTSTRAP
# -----------------------------------------------------------------------------
# hadolint ignore=DL3006
FROM --platform=$TARGETPLATFORM bootstrap-archlinux-${TARGETARCH}${TARGETVARIANT} AS bootstrap-archlinux

# Remove unecessary packages
# hadolint ignore=SC2086
RUN --network=none pacman -D --asdeps $(pacman -Qq) && \
                   pacman -D --asexplicit base && \
                   (unused_pkgs="$(pacman -Qqdt)"; \
                   if [ "$unused_pkgs" != "" ]; then \
                       pacman -Rcsun $unused_pkgs --noconfirm --noprogressbar ; \
                   fi )

# Update
RUN pacman -Syyu --noprogressbar --needed --noconfirm

# -----------------------------------------------------------------------------
# BASE
# -----------------------------------------------------------------------------
# hadolint ignore=DL3006
FROM --platform=$TARGETPLATFORM bootstrap-archlinux AS base-stage0

# Set default shell
SHELL [ "/bin/sh", "-c" ]
ENV SHELL=/bin/sh

# Install sudo
RUN pacman -Syyu sudo --noprogressbar --needed --noconfirm

# Add user, group wheel, setup sudoers, set correct locale and fix PAM session permissions
# hadolint ignore=SC2039
RUN --network=none /usr/sbin/useradd -m -G wheel -g users docker && \
                   /usr/sbin/echo -e "Defaults secure_path=\"/usr/local/sbin:/usr/local/bin:/usr/bin\"\n$(/usr/sbin/cat /etc/sudoers)" > /etc/sudoers && \
                   /usr/sbin/sed -i -e "s/Defaults    requiretty.*/ #Defaults    requiretty/g" /etc/sudoers && \
                   /usr/sbin/echo '%wheel ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/99-wheel-group && \
                   /usr/sbin/echo "LC_ALL=en_US.UTF-8" >> /etc/environment && \
                   /usr/sbin/echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen && \
                   /usr/sbin/echo "LANG=en_US.UTF-8" > /etc/locale.conf && \
                   /usr/sbin/locale-gen en_US.UTF-8 && \
                   /usr/sbin/sed -i 's/^\(session.*\)required\(.*pam_limits.so\)/\1optional\2/' /etc/pam.d/system-auth

# Set locale env
ENV LC_CTYPE 'en_US.UTF-8'

# hadolint ignore=DL3021
COPY --link ./generic/00-opt-session-pam.hook /etc/pacman.d/hooks/00-opt-session-pam.hook
COPY --link ./generic/00-package-cleanup.hook /etc/pacman.d/hooks/00-package-cleanup.hook

# Remove unrequired dependencies
# hadolint ignore=SC2086
RUN --network=none pacman -D --asdeps $(pacman -Qq) && \
                   pacman -D --asexplicit base sudo && \
                   (unused_pkgs="$(pacman -Qqdt)"; \
                   if [ "$unused_pkgs" != "" ]; then \
                       pacman -Rcsun $unused_pkgs --noconfirm --noprogressbar ; \
                   fi )

RUN pacman -Syyu --asexplicit base sudo --noprogressbar --noconfirm --overwrite '*'

# update trusted certs
RUN /usr/sbin/trust extract-compat && \
    /usr/sbin/update-ca-trust

# alias for FROM dependencies
FROM base-stage0 AS from-base

# -----------------------------------------------------------------------------
# LITE
# -----------------------------------------------------------------------------
FROM from-base AS lite-stage0

# hadolint ignore=SC2086
RUN pacman -Syyu busybox --noconfirm --noprogressbar && \
    pacman -D --asdeps $(pacman -Qq) && \
    pacman -D --asexplicit busybox pacman glibc && \
    (unused_pkgs="$(pacman -Qqdt)"; \
    if [ "$unused_pkgs" != "" ]; then \
        pacman -Rcsun $unused_pkgs --noconfirm --noprogressbar ; \
    fi )

# Substitute with busybox
SHELL [ "/usr/bin/busybox", "sh",  "-c" ]

# Remove coreutils and other linux utils
RUN pacman -Rndd gawk findutils grep bash coreutils --noconfirm --noprogressbar && \
    /usr/bin/busybox --install && \
    /usr/bin/find /usr/bin/ -type f | grep -vE 'pacman|busybox|xargs|rm|grep|find' | xargs -I{} rm -rf '{}' && \
    for b in $(busybox --list-full | grep -v busybox); do \
        ln -sf /usr/bin/busybox "/$b"; \
    done

# alias for FROM dependencies
FROM lite-stage0 AS from-lite

# -----------------------------------------------------------------------------
# DEVEL
# -----------------------------------------------------------------------------
FROM from-base AS devel-stage0

# Install base-devel and multilib-devel
RUN pacman -Syyu base-devel git --noprogressbar --needed --noconfirm

# alias for FROM dependencies
FROM devel-stage0 AS from-devel

# -----------------------------------------------------------------------------
# AUR
# -----------------------------------------------------------------------------
FROM from-devel AS aur-stage0

# Install yay
# hadolint ignore=DL3004,DL3003
RUN pacman -Syyu --noprogressbar --noconfirm && \
    cd /tmp && \
    git clone https://aur.archlinux.org/yay.git && \
    chown -R docker:wheel yay && \
    cd yay && \
    sudo -u docker makepkg -sic --noprogressbar --noconfirm && \
    cd .. && rm -rf yay && \
    rm -rf /var/cache/pacman/pkg/* && \
    rm -rf /var/lib/pacman/sync/* && \
    rm -rf /tmp/*

# alias for FROM dependencies
FROM aur-stage0 AS from-aur

# -----------------------------------------------------------------------------
# CLEANUP STAGES
# -----------------------------------------------------------------------------

FROM from-base AS base
COPY --link ./generic/cleanup /cleanup
RUN --network=none /cleanup && rm -rf /cleanup

FROM from-lite AS lite
COPY --link ./generic/cleanup /cleanup
RUN --network=none /cleanup && rm -rf /cleanup

FROM from-aur AS aur
COPY --link ./generic/cleanup /cleanup
RUN --network=none /cleanup && rm -rf /cleanup

FROM from-devel AS devel
COPY --link ./generic/cleanup /cleanup
RUN --network=none /cleanup && rm -rf /cleanup

# -----------------------------------------------------------------------------
# SQUASH STAGES
# -----------------------------------------------------------------------------

# Remove docker layers with multi-stage build
FROM scratch AS squash-stage

# set maintainer label
LABEL maintainer="Luís Ferreira <contact at lsferreira dot net>"

# Set common env vars
ENV LC_CTYPE 'en_US.UTF-8'
ENV LANG 'en_US.UTF-8'
ENV SHELL=/bin/sh

# Set default shell
SHELL [ "/bin/sh", "-c" ]

# Set workdir as /
WORKDIR /

FROM squash-stage AS lite-squash
COPY --from=lite / /

FROM squash-stage AS devel-squash
COPY --from=devel / /

FROM squash-stage AS aur-squash
COPY --from=aur / /

FROM squash-stage AS base-squash
COPY --from=base / /
