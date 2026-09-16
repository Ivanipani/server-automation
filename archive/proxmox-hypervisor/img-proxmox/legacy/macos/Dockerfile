FROM --platform=linux/amd64 debian:bookworm-slim

RUN apt-get update -qq && apt-get install -y wget ca-certificates xorriso

RUN wget -qO /etc/apt/trusted.gpg.d/proxmox-release-bookworm.gpg https://enterprise.proxmox.com/debian/proxmox-release-bookworm.gpg

RUN echo 'deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription' > /etc/apt/sources.list.d/pve.list

RUN apt-get update \
    && apt-get install -y proxmox-auto-install-assistant \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /work

ENTRYPOINT ["proxmox-auto-install-assistant"]
