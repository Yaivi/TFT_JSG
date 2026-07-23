#!/bin/bash
# stress_test.sh - Prueba de CAPACIDAD / LIMIT TESTING del laboratorio.
# Despliega N stacks de una asignatura en cadena, midiendo recursos en cada paso,
# hasta llegar a N o hasta que un despliegue falle (limite alcanzado).
#
# Ejecutar en el HOST (WSL/servidor), preferiblemente en un entorno LIMPIO
# (sin alumnos reales) para no chocar octetos ni falsear las medidas.
#
# Uso:
#   ./stress_test.sh <asignatura> <N> [paso] [base_octeto]
#       asignatura : rc | asr   (o cualquiera de ASIG_COMPOSE que tenga compose)
#       N          : cuantos stacks desplegar             (def. 20)
#       paso       : cada cuantos stacks registrar metrica (def. 5)
#       base_octeto: primer octeto a usar                 (def. 100)
#   ./stress_test.sh limpiar          # borra TODO lo que cree este test (prefijo 'stress')
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/comun.sh"

# --- modo limpieza ---
if [[ "${1:-}" == "limpiar" ]]; then
  echo "Limpiando contenedores y redes 'stress*'..."
  docker ps -aq --filter 'name=^stress' | xargs -r docker rm -f >/dev/null 2>&1
  docker network ls -q --filter 'name=^stress' | xargs -r docker network rm >/dev/null 2>&1
  echo "Hecho."
  exit 0
fi

asig="${1:-rc}"; N="${2:-20}"; PASO="${3:-5}"; BASE="${4:-100}"
compose="${ASIG_COMPOSE[$asig]:-}"
[[ -z "$compose" ]] && { echo "Asignatura desconocida: $asig (validas: ${!ASIG_COMPOSE[*]})"; exit 1; }
ruta="${COMPOSE_DIR}/${compose}"
[[ -f "$ruta" ]] || { echo "No existe el compose: $ruta"; exit 1; }

CSV="$DIR/stress_${asig}_$(date +%Y%m%d_%H%M%S).csv"
ERR="$DIR/stress_errores.log"; : > "$ERR"
echo "stacks,contenedores,mem_usada_MB,mem_disp_MB,load1,seg_deploy" > "$CSV"

# Limpieza automatica de restos de ejecuciones ANTERIORES del propio test, para
# que una tanda no colisione octetos/redes con la anterior (p. ej. rc y luego asr
# usando la misma base). Si quieres acumular carga de varias asignaturas a la vez,
# comenta estas dos lineas.
docker ps -aq --filter 'name=^stress' | xargs -r docker rm -f >/dev/null 2>&1
docker network ls -q --filter 'name=^stress' | xargs -r docker network rm >/dev/null 2>&1

metricas() {
  local stacks="$1" dt="$2" conts mem_u mem_a load
  conts=$(docker ps -q --filter 'name=^stress' | wc -l)
  mem_u=$(free -m | awk '/^Mem:/{print $3}')
  mem_a=$(free -m | awk '/^Mem:/{print $7}')
  load=$(awk '{print $1}' /proc/loadavg)
  echo "${stacks},${conts},${mem_u},${mem_a},${load},${dt}" >> "$CSV"
  printf "  stacks=%-4s conts=%-4s mem_usada=%sMB mem_disp=%sMB load=%s deploy=%ss\n" \
    "$stacks" "$conts" "$mem_u" "$mem_a" "$load" "$dt"
}

echo "== STRESS: asignatura=${asig}  N=${N}  paso=${PASO}  base_octeto=${BASE} =="
echo "== Imagen: construyendo una vez para no contar el build en los tiempos... =="
OCTETO="$BASE" docker compose -f "$ruta" build >/dev/null 2>>"$ERR" || echo "  (aviso: build dio error, mira $ERR)"

echo "== Desplegando =="
metricas 0 0   # linea base (sin stacks del test)
ultimo=0
for i in $(seq 1 "$N"); do
  proj="stress$(printf '%03d' "$i")-${asig}"
  oct=$(( BASE + i - 1 ))
  if (( oct > 255 )); then echo "  octeto > 255: tope del esquema de subredes, paro en $i."; break; fi
  t0=$(date +%s.%N)
  if ! OCTETO="$oct" docker compose -p "$proj" -f "$ruta" up -d >/dev/null 2>>"$ERR"; then
    echo "  >>> FALLO al desplegar el stack $i ($proj). LIMITE ALCANZADO."
    echo "  >>> Ultimas lineas del error:"; tail -3 "$ERR" | sed 's/^/      /'
    metricas "$i" 0
    ultimo="$i"; break
  fi
  t1=$(date +%s.%N)
  dt=$(awk -v a="$t0" -v b="$t1" 'BEGIN{printf "%.1f", b-a}')
  ultimo="$i"
  (( i % PASO == 0 )) && metricas "$i" "$dt"
done
metricas "$ultimo" 0   # medida final

echo
echo "== Resumen =="
echo "  Stacks desplegados: ${ultimo} de ${N}  (contenedores por stack: rc/asr = 3)"
echo "  CSV con la evolucion: ${CSV}"
echo "  Errores (si los hubo): ${ERR}"
echo "  Para borrar todo lo del test:  ./stress_test.sh limpiar"