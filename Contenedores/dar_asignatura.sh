#!/bin/bash
# dar_asignatura.sh - Tarea 3.4 (despliegue del puesto / creacion de contenedores).
# Despliega el stack de una asignatura para un usuario YA dado de alta y le
# concede los permisos (sudoers) sobre sus contenedores.
# Uso:  ./dar_asignatura.sh <usuario> <asignatura>
# Ej.:  ./dar_asignatura.sh alumno01 rc
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/comun.sh"
 
usuario="${1:-}"; asignatura="${2:-}"
if [[ -z "$usuario" || -z "$asignatura" ]]; then
  echo "Uso: $0 <usuario> <asignatura>   (validas: ${!ASIG_COMPOSE[*]})"; exit 1
fi
if [[ -z "${ASIG_COMPOSE[$asignatura]:-}" ]]; then
  echo "Asignatura desconocida: $asignatura   (validas: ${!ASIG_COMPOSE[*]})"; exit 1
fi
# El usuario debe existir ya en la pasarela (alta previa con usuario_nuevo.sh).
if ! docker exec "$GATEWAY" id "$usuario" >/dev/null 2>&1; then
  echo "ERROR: ${usuario} no existe en la pasarela. Primero:  ./usuario_nuevo.sh ${usuario}"; exit 1
fi
 
echo "== Despliegue de ${asignatura} para ${usuario} =="
crear_stack_alumno "$usuario" "$asignatura"   # 3.4 - crea el stack
actualizar_sudoers "$usuario"                  # permisos sobre TODOS sus contenedores
echo "Listo. ${usuario} arranca con:  sudo docker compose -p ${usuario}-${asignatura} start"
 