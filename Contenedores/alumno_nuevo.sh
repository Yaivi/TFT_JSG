#!/bin/bash
# alumno_nuevo.sh - Atajo del caso comun: alta de usuario (3.1/3.2) + despliegue
# de una asignatura (3.4) de una sola vez. Equivale a:
#   ./usuario_nuevo.sh <usuario> alumno   &&   ./dar_asignatura.sh <usuario> <asignatura>
# Uso:  ./alumno_nuevo.sh <usuario> <asignatura>
# Ej.:  ./alumno_nuevo.sh alumno01 rc
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
 
usuario="${1:-}"; asignatura="${2:-}"
if [[ -z "$usuario" || -z "$asignatura" ]]; then
  echo "Uso: $0 <usuario> <asignatura>"; exit 1
fi
 
"$DIR/usuario_nuevo.sh"  "$usuario" alumno
"$DIR/dar_asignatura.sh" "$usuario" "$asignatura"
 