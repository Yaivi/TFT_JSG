#!/bin/bash
# comun.sh - Config, catalogo de asignaturas (Compose) y funciones comunes.
# Se ejecuta en el HOST (donde corren Docker, la pasarela y el repositorio).
# La pasarela debe estar en marcha; gestionamos usuarios y reglas en caliente.

GATEWAY="${GATEWAY:-lab-gateway}"

# Contrasena inicial de los usuarios nuevos (pasarela y repositorio).
# En produccion: cambiala o usa claves SSH y fuerza el cambio en el primer acceso.
CLAVE_INICIAL="${CLAVE_INICIAL:-lab1234}"

# --- Rutas relativas a la UBICACION de este script (no al directorio actual) ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Compose de cada asignatura: ...\ARCHIVOS DESARROLLO\Dockerfiles\<asig>\docker-compose.yml
COMPOSE_DIR="${COMPOSE_DIR:-$(cd "$SCRIPT_DIR/.." && pwd)/Dockerfiles}"
# Pasarela y copia persistente de los sudoers junto a ella.
GATEWAY_DIR="${GATEWAY_DIR:-$SCRIPT_DIR/gateway}"
SUDOERS_DIR="${SUDOERS_DIR:-$GATEWAY_DIR/sudoers.d}"

# --- Repositorio de imagenes (Docker Registry + cesanta/docker_auth) ---
# AJUSTA estos dos valores a tu instalacion real.
REPO_AUTH_CONTAINER="${REPO_AUTH_CONTAINER:-docker_auth}"                      # contenedor docker_auth
REPO_AUTH_CONFIG="${REPO_AUTH_CONFIG:-$SCRIPT_DIR/registro/auth/auth_config.yml}"   # su YAML en el host

# --- Registro proyecto -> octeto (una subred unica por proyecto) ---
OCTETO_DB="${OCTETO_DB:-$SCRIPT_DIR/octetos.txt}"

# ====== CATALOGO DE ASIGNATURAS ======
declare -A ASIG_COMPOSE=(
  [rc]="RC/docker-compose.yml"
  [asr]="ASR/docker-compose.yml"
)
declare -A ASIG_ROLES=(
  [rc]="cliente router servidor"
  [asr]="pasarela servidor cliente"
)

# ====== FUNCIONES AUXILIARES ======

proyecto_de() { echo "${1}-${2}"; }

contenedores_de() {
  docker ps -a --filter "name=^$1-" --format '{{.Names}}'
}

# Devuelve el octeto del proyecto; si no tiene, le asigna el siguiente libre (1..254).
octeto_de() {
  local proyecto="$1" n
  touch "$OCTETO_DB"
  n="$(awk -v p="$proyecto" '$1==p{print $2}' "$OCTETO_DB")"
  if [[ -z "$n" ]]; then
    n="$(awk 'BEGIN{m=0}{if($2+0>m)m=$2+0}END{print m+1}' "$OCTETO_DB")"
    echo "$proyecto $n" >> "$OCTETO_DB"
  fi
  echo "$n"
}

# ====== GESTION DE USUARIOS (tareas 3.1 / 3.2) ======

# 3.1 - Crea el usuario del SO en la pasarela con una contrasena inicial.
crear_usuario_gateway() {
  local usuario="$1"
  if docker exec "$GATEWAY" id "$usuario" >/dev/null 2>&1; then
    echo "  usuario ${usuario} ya existe en la pasarela"
  else
    docker exec "$GATEWAY" useradd -m -s /bin/bash "$usuario"
    docker exec "$GATEWAY" bash -c "echo '${usuario}:${CLAVE_INICIAL}' | chpasswd"
    echo "  usuario ${usuario} creado en la pasarela (contrasena: ${CLAVE_INICIAL})"
  fi
}

# 3.2 - Crea/actualiza el usuario en el repositorio (docker_auth).
# rol: 'alumno' (solo pull) o 'profesor' (acceso total). Por defecto, alumno.
crear_usuario_repo() {
  local usuario="$1" rol="${2:-alumno}" hash
  for cmd in htpasswd yq; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "  ERROR: falta '$cmd'; el usuario NO se creo en el repositorio" >&2; return 1; }
  done
  # 1) hash bcrypt de la contrasena (htpasswd -B -> formato $2y$, coste 5)
  hash="$(htpasswd -Bbn "$usuario" "$CLAVE_INICIAL" | cut -d: -f2-)"
  # 2) anadir/actualizar el usuario y su etiqueta de grupo. strenv() evita que
  #    los '$' del hash bcrypt rompan la expresion de yq.
  USR="$usuario" HASH="$hash" ROL="$rol" yq -i '
      .users[strenv(USR)].password = strenv(HASH) |
      .users[strenv(USR)].labels.group = [strenv(ROL)]
    ' "$REPO_AUTH_CONFIG" || { echo "  ERROR: yq no pudo editar $REPO_AUTH_CONFIG" >&2; return 1; }
  # 3) recargar docker_auth para que lea el nuevo usuario
  docker restart "$REPO_AUTH_CONTAINER" >/dev/null 2>&1 \
    || echo "  AVISO: no pude reiniciar ${REPO_AUTH_CONTAINER}; reinicialo a mano"
  echo "  usuario ${usuario} en el repositorio (grupo: ${rol}, contrasena: ${CLAVE_INICIAL})"
}

# ====== CREACION DE CONTENEDORES / DESPLIEGUE DEL PUESTO (tarea 3.4) ======

# Crea el stack de una asignatura para un usuario, con su nombre como proyecto
# (Compose namespacea todo) y un OCTETO unico para que las subredes no choquen.
crear_stack_alumno() {
  local usuario="$1" asignatura="$2"
  local compose="${ASIG_COMPOSE[$asignatura]:-}"
  [[ -z "$compose" ]] && { echo "  ERROR: asignatura sin compose: $asignatura" >&2; return 1; }
  local ruta="${COMPOSE_DIR}/${compose}"
  [[ ! -f "$ruta" ]] && { echo "  ERROR: no existe el compose: $ruta" >&2; return 1; }
  local proyecto; proyecto="$(proyecto_de "$usuario" "$asignatura")"
  local octeto;   octeto="$(octeto_de "$proyecto")"
  ALUMNO="$usuario" OCTETO="$octeto" docker compose -p "$proyecto" -f "$ruta" create
  echo "  stack '${proyecto}' creado (octeto ${octeto})"
}

# (Re)genera el sudoers del usuario con TODOS sus contenedores: copia persistente
# en el host + aplicacion en caliente en la pasarela (root:root, 0440, validado).
actualizar_sudoers() {
  local usuario="$1" c
  mkdir -p "$SUDOERS_DIR"
  local host_file="$SUDOERS_DIR/$usuario"
  {
    echo "# Generado automaticamente. No editar a mano."
    # Encender / apagar la asignatura entera (proyecto Compose). El comodin va
    # en MEDIO (la regla termina en 'start'/'stop'), por eso es cerrada y segura.
    echo "${usuario} ALL=(root) NOPASSWD: /usr/bin/docker compose -p ${usuario}-* start"
    echo "${usuario} ALL=(root) NOPASSWD: /usr/bin/docker compose -p ${usuario}-* stop"
    # Ver SOLO sus contenedores.
    echo "${usuario} ALL=(root) NOPASSWD: /usr/bin/docker ps -a --filter name=^${usuario}-"
    # Por cada contenedor suyo: encender / apagar / entrar, con NOMBRE EXACTO
    # (sin comodin final, para que no pueda colar contenedores de otros usuarios).
    for c in $(contenedores_de "$usuario"); do
      echo "${usuario} ALL=(root) NOPASSWD: /usr/bin/docker start ${c}"
      echo "${usuario} ALL=(root) NOPASSWD: /usr/bin/docker stop ${c}"
      echo "${usuario} ALL=(root) NOPASSWD: /usr/bin/docker exec -it ${c} bash"
    done
  } > "$host_file"

  docker cp "$host_file" "${GATEWAY}:/etc/sudoers.d/${usuario}.tmp"
  if docker exec "$GATEWAY" visudo -c -f "/etc/sudoers.d/${usuario}.tmp" >/dev/null 2>&1; then
    docker exec "$GATEWAY" bash -c \
      "mv /etc/sudoers.d/${usuario}.tmp /etc/sudoers.d/${usuario} && chown root:root /etc/sudoers.d/${usuario} && chmod 0440 /etc/sudoers.d/${usuario}"
    echo "  sudoers de ${usuario} guardado en ${host_file} y aplicado"
  else
    docker exec "$GATEWAY" rm -f "/etc/sudoers.d/${usuario}.tmp"
    rm -f "$host_file"
    echo "  ERROR: sudoers invalido para ${usuario}" >&2
    return 1
  fi
}