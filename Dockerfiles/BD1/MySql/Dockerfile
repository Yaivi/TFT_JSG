# =============================================================================
# Base de Datos 1  ·  Modelo DISTRIBUIDO  ·  Variante MySQL
# -----------------------------------------------------------------------------
# SGBD: MySQL 8.4 LTS (cliente mysql incluido en la imagen).
# La imagen oficial de MySQL está basada en Oracle Linux, no hace falta una imagen 
# de Linux debajo ya la tiene la propia imagen de mysql, así que
# no se usa apt-get/locales; la codificación se fija con utf8mb4 (acentos ES).
# =============================================================================
FROM mysql:8.4

# --- Credenciales y base de datos por defecto (entorno docente) --------------
ENV MYSQL_ROOT_PASSWORD=root
ENV MYSQL_DATABASE=bd1
ENV MYSQL_USER=alumno
ENV MYSQL_PASSWORD=alumno

# --- Scripts que se ejecutan SOLO la primera vez (al crear el volumen) --------
COPY init /docker-entrypoint-initdb.d/

EXPOSE 3306

# Codificación utf8mb4 para acentos y caracteres en español
CMD ["mysqld", "--character-set-server=utf8mb4", "--collation-server=utf8mb4_unicode_ci"]

# USO:
#   docker build -t bd1-mysql .
#   docker run -d --name bd1 -p 3306:3306 bd1-mysql
#   docker exec -it bd1 mysql -u alumno -palumno bd1
