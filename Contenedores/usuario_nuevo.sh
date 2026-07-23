#!/bin/bash
# Uso:  ./usuario_nuevo.sh <usuario> [alumno|profesor]
# Ej.:  ./usuario_nuevo.sh alumno01
#       ./usuario_nuevo.sh prof_ana profesor
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/comun.sh"
 
usuario="${1:-}"; rol="${2:-alumno}"
[[ -z "$usuario" ]] && { echo "Uso: $0 <usuario> [alumno|profesor]"; exit 1; }
 
echo "== Alta de usuario ${usuario} (${rol}) =="
crear_usuario_gateway "$usuario"           # 3.1 - cuenta SSH en la pasarela
crear_usuario_repo    "$usuario" "$rol"    # 3.2 - credenciales del repositorio
echo "Listo:"
echo "  - SSH a la pasarela:  ssh ${usuario}@<servidor> -p 2222   (clave: ${CLAVE_INICIAL})"
echo "  - Login en el repo:   docker login <repo> -u ${usuario}    (clave: ${CLAVE_INICIAL})"
 