# =============================================================================
# ASR · PASARELA (gateway)
# -----------------------------------------------------------------------------
# Intermediaria entre la red interna del laboratorio y la red externa.
# Realiza el encaminamiento y las reglas de firewall (NAT, filtrado).
# =============================================================================
FROM debian:12

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        iproute2 iputils-ping net-tools traceroute \
        iptables nftables \
        dnsutils tcpdump \
        nano vim less procps sudo ca-certificates \
 && rm -rf /var/lib/apt/lists/*

RUN useradd -m -s /bin/bash alumno \
 && echo "alumno:alumno" | chpasswd \
 && usermod -aG sudo alumno \
 && echo "alumno ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/alumno \
 && mkdir -p /run/sshd


WORKDIR /root
# El alumno configura el reenvío y las reglas (iptables/nft) durante la práctica.
CMD ["sleep", "infinity"]
