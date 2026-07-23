# =============================================================================
# Redes de Computadores  ·  Modelo MONOLÍTICO (nodo de red genérico)
# -----------------------------------------------------------------------------
# Imagen base común para los distintos nodos (cliente, router, servidor) que
# sustituyen a las máquinas virtuales + router físico del laboratorio.
# Incluye herramientas de configuración TCP/IP, DHCP, captura/análisis de
# tráfico (tshark = Wireshark CLI), enrutamiento y diagnóstico.
#
# Se usa Debian 12 por la disponibilidad estable de isc-dhcp-server/-client.
# Para configurar IPs, rutas o capturar tráfico, los contenedores deben
# lanzarse con la capacidad NET_ADMIN (ya configurado en docker-compose.yml).
# =============================================================================
FROM debian:12

ENV DEBIAN_FRONTEND=noninteractive

# Acepta de antemano la opción de captura sin root de wireshark-common
RUN echo "wireshark-common wireshark-common/install-setuid boolean true" | debconf-set-selections \
 && apt-get update && apt-get install -y --no-install-recommends \
        iproute2 iputils-ping net-tools traceroute mtr-tiny \
        isc-dhcp-client isc-dhcp-server \
        tcpdump tshark \
        dnsutils iptables nftables \
        nano vim less procps sudo ca-certificates \
 && rm -rf /var/lib/apt/lists/*

RUN useradd -m -s /bin/bash alumno \
 && echo "alumno:alumno" | chpasswd \
 && usermod -aG sudo alumno \
 && echo "alumno ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/alumno \
 && mkdir -p /run/sshd

 
WORKDIR /root

# Mantiene el contenedor vivo aunque no haya terminal interactiva conectada;
# el alumno entra con: docker exec -it <nombre> bash
CMD ["sleep", "infinity"]
