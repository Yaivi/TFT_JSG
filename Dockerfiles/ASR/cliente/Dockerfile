# =============================================================================
# ASR · CLIENTE
# -----------------------------------------------------------------------------
# Estación desde la que se comprueban los servicios del servidor: resolución
# DNS (dig), correo (cliente SMTP/IMAP/POP3), acceso remoto (ssh/sftp) y
# diagnóstico de red (ping, ss, traceroute).
# =============================================================================
FROM debian:12

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        dnsutils iproute2 iputils-ping net-tools traceroute \
        openssh-client \
        mailutils swaks \
        curl ca-certificates \
        nano vim less procps sudo \
 && rm -rf /var/lib/apt/lists/*

RUN useradd -m -s /bin/bash alumno \
 && echo "alumno:alumno" | chpasswd \
 && usermod -aG sudo alumno \
 && echo "alumno ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/alumno \
 && mkdir -p /run/sshd


WORKDIR /root
CMD ["sleep", "infinity"]

# Herramientas útiles dentro del contenedor:
#   dig @<ip_servidor> laboratorio.local
#   swaks --to user@laboratorio.local --server <ip_servidor>   (probar SMTP)
#   ssh alumno@<ip_servidor>   /   sftp alumno@<ip_servidor>
