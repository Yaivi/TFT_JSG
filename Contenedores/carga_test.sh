#!/bin/bash
# carga_test.sh - Consumo de recursos con contenedores ACTIVOS.
# Genera carga de CPU DENTRO de los contenedores (no solo encendidos) y barre
# distintos PORCENTAJES de contenedores activos, midiendo el consumo en cada uno.
# La "cantidad" de contenedores la fijas tu desplegando mas o menos puestos antes
# (con stress_test.sh o stress_limite.sh); este script barre el porcentaje activo.
#
# La carga es CPU (procesos 'yes' acotados con 'timeout'), que es el recurso
# representativo en las practicas de red. Se auto-detiene por tiempo.
#
# Uso:
#   ./carga_test.sh [filtro] [workers] [dur] [porcentajes]
#     filtro     : prefijo de los contenedores a usar (def. "stress")
#     workers    : procesos de CPU por contenedor cargado (def. 1)
#     dur        : segundos que dura cada escalon (def. 25)
#     porcentajes: lista separada por comas (def. "0,25,50,75,100")
#   Ej.:  ./carga_test.sh stress 1 25 0,25,50,75,100
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"

FILTRO="${1:-stress}"
WORKERS="${2:-1}"
DUR="${3:-25}"
IFS=',' read -r -a PCTS <<< "${4:-0,25,50,75,100}"
RAMP=6   # segundos antes de medir, para que la carga suba

mapfile -t IDS < <(docker ps -q --filter "name=^${FILTRO}")
TOTAL="${#IDS[@]}"
(( TOTAL == 0 )) && { echo "No hay contenedores en marcha con prefijo '${FILTRO}'. Arranca puestos primero."; exit 1; }

CSV="$DIR/carga_$(date +%Y%m%d_%H%M%S).csv"
echo "pct_activos,cargados,total,workers,cpu_total_pct,mem_usada_MB,mem_disp_MB,load1" > "$CSV"

muestra() {
  local pct="$1" nload="$2" cpu memu memd load
  # suma del %CPU de TODOS los contenedores (loaded + idle)
  cpu=$(docker stats --no-stream --format '{{.CPUPerc}}' "${IDS[@]}" 2>/dev/null \
        | tr -d '%' | awk '{s+=$1} END{printf "%.0f", s}')
  memu=$(free -m | awk '/^Mem:/{print $3}')
  memd=$(free -m | awk '/^Mem:/{print $7}')
  load=$(awk '{print $1}' /proc/loadavg)
  echo "${pct},${nload},${TOTAL},${WORKERS},${cpu},${memu},${memd},${load}" >> "$CSV"
  printf "  activos=%-4s cargados=%-4s/%-4s cpu_total=%s%%  mem_usada=%sMB  load=%s\n" \
    "${pct}%" "$nload" "$TOTAL" "$cpu" "$memu" "$load"
}

echo "== CARGA: ${TOTAL} contenedores '${FILTRO}', ${WORKERS} worker(s)/contenedor, ${DUR}s por escalon =="
for pct in "${PCTS[@]}"; do
  nload=$(( TOTAL * pct / 100 ))
  # arrancar carga acotada por tiempo en los primeros 'nload' contenedores
  for (( k=0; k<nload; k++ )); do
    docker exec -d "${IDS[$k]}" sh -c \
      "for i in \$(seq 1 ${WORKERS}); do timeout ${DUR} yes >/dev/null 2>&1 & done" 2>/dev/null
  done
  sleep "$RAMP"
  muestra "$pct" "$nload"
  # esperar a que termine el escalon (la carga se apaga sola por 'timeout')
  resto=$(( DUR - RAMP + 3 )); (( resto > 0 )) && sleep "$resto"
done

echo "== Fin. CSV: ${CSV} =="
echo "   La carga se detiene sola (timeout). Si quedara algun 'yes' suelto,"
echo "   reinicia esos contenedores para pararlo."