#!/bin/bash
# stress_limite.sh - Prueba "hasta el limite".
# Despliega puestos SIN TOPE fijo, ALTERNANDO asignaturas (rc, asr, rc, asr...),
# con un octeto UNICO por puesto (para que nunca choquen), y registra cada uno
# en un CSV. Se detiene cuando:
#   - un despliegue falla (limite real: memoria/red), o
#   - la memoria disponible baja del suelo de seguridad, o
#   - se agota el octeto (255, tope del esquema de subredes).
#
# SEGURIDAD: en Docker Desktop es seguro (la VM tiene la RAM acotada, no tumba
# Windows). En un servidor Linux real, llevarlo al agotamiento total puede
# congelar la maquina; por eso hay un suelo de memoria por defecto. NO se busca
# apagar el equipo a proposito (riesgo de perdida de datos): se para en el borde.
#
# Uso:
#   ./stress_limite.sh [asignaturas] [suelo_mem_MB] [base_octeto]
#       asignaturas : lista separada por comas (def. "rc,asr"); se alternan
#       suelo_mem_MB: para si la mem. disponible baja de esto (def. 400; 0 = sin suelo)
#       base_octeto : primer octeto (def. 1)
#   ./stress_limite.sh limpiar
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/comun.sh"

# --- modo limpieza ---
if [[ "${1:-}" == "limpiar" ]]; then
  echo "Limpiando 'stress*'..."
  docker ps -aq --filter 'name=^stress' | xargs -r docker rm -f >/dev/null 2>&1
  docker network ls -q --filter 'name=^stress' | xargs -r docker network rm >/dev/null 2>&1
  echo "Hecho."; exit 0
fi

IFS=',' read -r -a ASIGS <<< "${1:-rc,asr}"
SUELO="${2:-400}"      # MB de memoria disponible por debajo de la cual paramos
BASE="${3:-1}"

# validar asignaturas
for a in "${ASIGS[@]}"; do
  [[ -n "${ASIG_COMPOSE[$a]:-}" ]] || { echo "Asignatura desconocida: $a (validas: ${!ASIG_COMPOSE[*]})"; exit 1; }
done

ERR="$DIR/stress_errores.log"; : > "$ERR"

# pre-construir imagenes (para no contar el build en los tiempos)
echo "== Pre-construyendo imagenes =="
for a in "${ASIGS[@]}"; do
  OCTETO="$BASE" docker compose -f "${COMPOSE_DIR}/${ASIG_COMPOSE[$a]}" build >/dev/null 2>>"$ERR" \
    || echo "  (aviso: build de $a dio error, mira $ERR)"
done

# limpiar restos previos del propio test
docker ps -aq --filter 'name=^stress' | xargs -r docker rm -f >/dev/null 2>&1
docker network ls -q --filter 'name=^stress' | xargs -r docker network rm >/dev/null 2>&1

CSV="$DIR/limite_$(date +%Y%m%d_%H%M%S).csv"
echo "n_stack,asignatura,octeto,contenedores,mem_usada_MB,mem_disp_MB,load1,seg_deploy,estado" > "$CSV"

mem_disp() { free -m | awk '/^Mem:/{print $7}'; }

echo "== LIMITE: asignaturas=[${ASIGS[*]}]  suelo_mem=${SUELO}MB  base_octeto=${BASE} =="
echo "== Se despliega hasta que falle o baje del suelo de memoria. Ctrl-C para abortar. =="

i=0
while :; do
  oct=$(( BASE + i ))
  if (( oct > 255 )); then
    echo ">>> Octeto agotado (255): se ha alcanzado el tope del esquema de subredes."
    break
  fi

  # suelo de seguridad ANTES de intentar el siguiente
  libre=$(mem_disp)
  if (( SUELO > 0 && libre < SUELO )); then
    echo ">>> Memoria disponible ${libre}MB por debajo del suelo (${SUELO}MB). Paro por seguridad."
    break
  fi

  asg="${ASIGS[$(( i % ${#ASIGS[@]} ))]}"          # alterna rc, asr, rc, asr...
  proj="stress$(printf '%04d' "$i")-${asg}"
  ruta="${COMPOSE_DIR}/${ASIG_COMPOSE[$asg]}"

  t0=$(date +%s.%N)
  if OCTETO="$oct" docker compose -p "$proj" -f "$ruta" up -d >/dev/null 2>>"$ERR"; then
    estado=ok
  else
    estado=FALLO
  fi
  t1=$(date +%s.%N)
  dt=$(awk -v a="$t0" -v b="$t1" 'BEGIN{printf "%.1f", b-a}')

  conts=$(docker ps -q --filter 'name=^stress' | wc -l)
  memu=$(free -m | awk '/^Mem:/{print $3}')
  memd=$(mem_disp)
  load=$(awk '{print $1}' /proc/loadavg)
  echo "${i},${asg},${oct},${conts},${memu},${memd},${load},${dt},${estado}" >> "$CSV"
  printf "n=%-4s %-3s oct=%-3s conts=%-4s mem_disp=%sMB load=%s %s\n" \
    "$i" "$asg" "$oct" "$conts" "$memd" "$load" "$estado"

  if [[ "$estado" == "FALLO" ]]; then
    echo ">>> Despliegue FALLIDO en el puesto ${i}. LIMITE REAL ALCANZADO."
    echo ">>> Ultimas lineas del error:"; tail -3 "$ERR" | sed 's/^/    /'
    break
  fi
  i=$(( i + 1 ))
done

echo
echo "== Fin. Puestos desplegados: ${i}. Contenedores: $(docker ps -q --filter 'name=^stress' | wc -l). =="
echo "   CSV: ${CSV}"
echo "   Limpieza:  ./stress_limite.sh limpiar"