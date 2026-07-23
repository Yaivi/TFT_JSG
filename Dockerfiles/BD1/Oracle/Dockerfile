# =============================================================================
# Base de Datos 1  ·  Modelo DISTRIBUIDO  ·  Variante Oracle
# -----------------------------------------------------------------------------
# SGBD: Oracle Database 23ai Free (imagen gvenzl/oracle-free, gratuita en Docker
# Hub y muy usada en docencia; cliente sqlplus incluido).
#   Alternativa "oficial": container-registry.oracle.com/database/free
#   (requiere aceptar la licencia e iniciar sesión en el registro).
#
# AVISO: Oracle Database solo corre en x86_64/AMD64, NO en ARM (p. ej. Apple
# Silicon). Coincide con el hardware previsto en la memoria del TFG.
# =============================================================================
FROM gvenzl/oracle-free:23-slim

# --- Contraseña de SYS/SYSTEM y usuario de aplicación (entorno docente) -------
ENV ORACLE_PASSWORD=oracle
ENV APP_USER=alumno
ENV APP_USER_PASSWORD=alumno
ENV ORACLE_DATABASE=BD1         

# --- Scripts de inicialización (OJO: ruta distinta a MySQL/PostgreSQL) --------
COPY init /container-entrypoint-initdb.d/

EXPOSE 1521

# USO:
#   docker build -t bd1-oracle .
#   docker run -d --name bd1 -p 1521:1521 bd1-oracle
#   docker exec -it bd1 sqlplus alumno/alumno@//localhost:1521/BD1