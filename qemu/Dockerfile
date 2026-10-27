FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates cloud-image-utils curl ovmf qemu-system-x86 qemu-utils \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /opt/lfcs && \
    curl -fsSL https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img \
      -o /opt/lfcs/jammy-server-cloudimg-amd64.img && \
    curl -fsSL https://cloud-images.ubuntu.com/jammy/current/SHA256SUMS -o /tmp/SHA256SUMS && \
    cd /opt/lfcs && grep 'jammy-server-cloudimg-amd64.img$' /tmp/SHA256SUMS | sha256sum -c - && \
    rm /tmp/SHA256SUMS

COPY qemu-entrypoint.sh /usr/local/bin/qemu-entrypoint
RUN chmod 755 /usr/local/bin/qemu-entrypoint

EXPOSE 2222
ENTRYPOINT ["/usr/local/bin/qemu-entrypoint"]
