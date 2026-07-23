# =============================================================================
# Base de Datos 2  ·  Modelo HÍBRIDO  ·  Variante MySQL
# -----------------------------------------------------------------------------
# Igual que la versión PostgreSQL: el alumno instala/configura/administra el
# SGBD por sí mismo (diseño físico, transacciones, concurrencia, copias de
# seguridad, recuperación, disparadores, procedimientos...). El servidor MySQL
# viene instalado pero DETENIDO; lo gestiona el alumno:
#   sudo service mysql start | stop | status
# =============================================================================
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        mysql-server mysql-client \
        sudo nano vim less iproute2 procps \
        locales ca-certificates \
 && localedef -i es_ES -c -f UTF-8 -A /usr/share/locale/locale.alias es_ES.UTF-8 \
 && rm -rf /var/lib/apt/lists/*
ENV LANG=es_ES.UTF-8

# --- Usuario administrador del entorno (con sudo) ----------------------------
RUN useradd -m -s /bin/bash alumno \
 && echo "alumno:alumno" | chpasswd \
 && usermod -aG sudo alumno \
 && echo "alumno ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/alumno

USER alumno
WORKDIR /home/alumno

CMD ["/bin/bash"]

# USO (contenedor interactivo y persistente):
#   docker build -t bd2-mysql .
#   docker run -it --name bd2 -p 3306:3306 bd2-mysql
# Dentro del contenedor:
#   sudo service mysql start
#   sudo mysql                 # acceso root por socket local
# Si el directorio de datos no estuviera inicializado:
#   sudo mysqld --initialize