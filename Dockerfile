# syntax=docker/dockerfile:1.4
# hadolint ignore=DL3007
FROM archlinux:latest AS base

# Copy custom configs
# hadolint ignore=DL3021
COPY --link pacman.conf /etc/pacman.conf
# hadolint ignore=DL3021
COPY --link makepkg.conf /etc/makepkg.conf

# Init keyring
RUN pacman-key --init && \
    pacman-key --populate archlinux

# Install base-devel and git
RUN pacman -Syyu base-devel git --noprogressbar --needed --noconfirm

# Add user, group wheel and setup sudoers
# hadolint ignore=SC2039
RUN /usr/sbin/useradd -m -G wheel -g users docker && \
    /usr/sbin/echo -e "Defaults secure_path=\"/usr/local/sbin:/usr/local/bin:/usr/bin\"\n$(/usr/sbin/cat /etc/sudoers)" > /etc/sudoers && \
    /usr/sbin/sed -i -e "s/Defaults    requiretty.*/ #Defaults    requiretty/g" /etc/sudoers && \
    /usr/sbin/echo '%wheel ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/99-wheel-group

WORKDIR /home/docker/

# Install yay
# hadolint ignore=DL3004,DL3003
RUN cd /tmp && \
    git clone https://aur.archlinux.org/yay.git && \
    chown -R docker:wheel yay && \
    cd yay && \
    sudo -u docker makepkg -sic --noprogressbar --noconfirm && \
    cd .. && rm -rf yay

# Use bash shell
ENV SHELL=/bin/bash

# Set correct locale
RUN /usr/sbin/echo "LC_ALL=en_US.UTF-8" >> /etc/environment && \
    /usr/sbin/echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen && \
    /usr/sbin/echo "LANG=en_US.UTF-8" > /etc/locale.conf && \
    locale-gen en_US.UTF-8
ENV LC_CTYPE 'en_US.UTF-8'

# Fix PAM session permissions
RUN sed -i 's/^\(session.*\)required\(.*pam_limits.so\)/\1optional\2/' /etc/pam.d/system-auth
# hadolint ignore=DL3021
COPY --link 00-opt-session-pam.hook /etc/pacman.d/hooks/00-opt-session-pam.hook

# Remove unrequired dependencies
# hadolint ignore=SC2086
RUN pacman -D --asdeps $(pacman -Qqe) && \
    pacman -D --asexplicit yay && \
    pacman -Rscu --noprogressbar --noconfirm base-devel git && \
    pacman -S --asexplicit base --noprogressbar --noconfirm && \
    (unused_pkgs="$(pacman -Qqdt)"; \
    if [ "$unused_pkgs" != "" ]; then \
        pacman -Rns $unused_pkgs --noconfirm --noprogressbar ; \
    fi )

# Remove cache and update trusted certs
RUN rm -rf /var/cache/pacman/pkg/* && \
    rm -rf /var/lib/pacman/sync/* && \
    rm -rf /tmp/* && \
    trust extract-compat

# Remove docker layers with multi-stage build
# hadolint ignore=DL3007
FROM archlinux:latest
LABEL maintainer="Luís Ferreira <contact at lsferreira dot net>"
ENV LC_CTYPE 'en_US.UTF-8'
ENV SHELL=/bin/bash
COPY --link --from=base / /
WORKDIR /
