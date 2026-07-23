# =============================================================================
# ASR · SERVIDOR
# -----------------------------------------------------------------------------
# Aloja los servicios de red que se configuran a lo largo de las prácticas:
#   - DNS              -> bind9 (zonas directas e inversas)
#   - Correo SMTP      -> Postfix
#   - Buzones IMAP/POP3-> Dovecot
#   - Acceso remoto    -> OpenSSH (SSH y SFTP)
#
# Los servicios se instalan pero se gestionan/arrancan manualmente por el
# alumno (objetivo de aprendizaje):  sudo service <servicio> start
# =============================================================================
FROM debian:12

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        bind9 bind9-utils dnsutils \
        postfix \
        dovecot-imapd dovecot-pop3d \
        openssh-server \
        telnet \
        iproute2 iputils-ping net-tools \
        nano vim less procps sudo ca-certificates rsyslog \
 && rm -rf /var/lib/apt/lists/*


RUN useradd -m -s /bin/bash alumno \
 && echo "alumno:alumno" | chpasswd \
 && usermod -aG sudo alumno \
 && echo "alumno ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/alumno \
 && mkdir -p /run/sshd

WORKDIR /root
# Arranque manual de servicios:
#   sudo service named  start   (DNS / bind9)
#   sudo service postfix start
#   sudo service dovecot start
#   sudo service ssh     start
CMD ["sleep", "infinity"]
