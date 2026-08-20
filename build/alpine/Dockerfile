FROM alpine:3.19

RUN printf '%s\n' \
      'https://dl-cdn.alpinelinux.org/alpine/v3.19/main' \
      'https://dl-cdn.alpinelinux.org/alpine/v3.19/community' \
      > /etc/apk/repositories \
    && apk add --no-cache \
      abuild apk-tools bash grub-bios grub-efi mtools openssl squashfs-tools tar xorriso

WORKDIR /workspace
