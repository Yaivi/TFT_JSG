#!/usr/bin/env bash
# ============================================================================
#  Propagar el Portainer Agent a un rango de maquinas via SSH. 
#  Entra por SSH a cada IP del rango.Levanta el agente con --restart=always 
#
#  Requisitos:
#    * Acceso SSH por clave a todas las maquinas con el usuario indicado.
#    * Ese usuario debe poder ejecutar 'sudo docker' SIN contrasena (NOPASSWD),
#      porque la sesion SSH es no interactiva. Ver nota al final del fichero.
# ============================================================================

set -uo pipefail 

# ----------------------------- CONFIGURACION --------------------------------
SSH_USER="admin"          # aqui va el usuario con sudo en las maquinas destino
IP_PREFIX="192.168.0"     # los tres primeros octetos de la red del laboratorio
IP_START=10               # ultimo octeto con valor inicial del rango
IP_END=50                 # ultimo octeto con valor final del rango 

COMPOSE_FILE="./docker-compose.agent.yml"   # fichero local que se propaga
REMOTE_FILE="docker-compose.agent.yml"      # nombre con el que se guarda en el HOME remoto
 
DRY_RUN=false             # true = solo muestra lo que haria, sin tocar nada
 
# Opciones SSH/SCP: no colgarse, no preguntar por contrasena ni host key
SSH_OPTS="-o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=accept-new"
# ----------------------------------------------------------------------------
 
# Comando que se ejecuta DENTRO de cada maquina remota.
# nada se expande en local; $HOME y $DC se resuelven en la maquina remota.
read -r -d '' REMOTE_CMD <<'EOF'
command -v docker >/dev/null 2>&1 || { echo 'SIN_DOCKER'; exit 2; }
if docker compose version >/dev/null 2>&1; then
  DC="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
  DC="docker-compose"
else
  echo 'SIN_COMPOSE'; exit 3
fi
sudo $DC -f "$HOME/docker-compose.agent.yml" up -d >/dev/null 2>&1
EOF
 
# Verifica que el fichero compose local existe antes de empezar
if [ ! -f "$COMPOSE_FILE" ]; then
    echo "ERROR: no se encuentra '$COMPOSE_FILE' en el directorio actual." >&2
    exit 1
fi
 
# Contadores para el resumen final
ok=0; sin_docker=0; sin_compose=0; inaccesibles=0; errores=0
total=$(( IP_END - IP_START + 1 ))
 
echo "============================================================"
echo " Propagando agente desde: ${COMPOSE_FILE}"
echo " Rango: ${IP_PREFIX}.${IP_START} - ${IP_PREFIX}.${IP_END}  (${total} maquinas)"
[ "$DRY_RUN" = true ] && echo " *** MODO DRY-RUN: no se ejecuta nada ***"
echo "============================================================"
 
for octeto in $(seq "$IP_START" "$IP_END"); do
    ip="${IP_PREFIX}.${octeto}"
    printf " %-15s ... " "$ip"
 
    if [ "$DRY_RUN" = true ]; then
        echo "[DRY-RUN]"
        continue
    fi
 
    # 1) Copiar el compose a la maquina (esto tambien sirve de test de conexion)
    if ! scp $SSH_OPTS "$COMPOSE_FILE" "${SSH_USER}@${ip}:${REMOTE_FILE}" >/dev/null 2>&1; then
        echo "[FALLO] inaccesible (apagada o sin SSH)"
        inaccesibles=$(( inaccesibles + 1 ))
        continue
    fi
 
    # 2) Levantar el agente con docker compose
    salida=$(ssh $SSH_OPTS "${SSH_USER}@${ip}" "$REMOTE_CMD" 2>&1)
    codigo=$?
 
    case "$codigo" in
        0)   echo "[OK] agente levantado";          ok=$(( ok + 1 )) ;;
        2)   echo "[AVISO] Docker no instalado";     sin_docker=$(( sin_docker + 1 )) ;;
        3)   echo "[AVISO] docker compose no disponible"; sin_compose=$(( sin_compose + 1 )) ;;
        255) echo "[FALLO] inaccesible (sin SSH)";   inaccesibles=$(( inaccesibles + 1 )) ;;
        *)   echo "[ERROR] codigo ${codigo}: ${salida}"; errores=$(( errores + 1 )) ;;
    esac
done
 
echo "============================================================"
echo " RESUMEN"
echo "   Correctas         : ${ok}"
echo "   Sin Docker        : ${sin_docker}"
echo "   Sin docker compose: ${sin_compose}"
echo "   Inaccesibles      : ${inaccesibles}"
echo "   Otros errores     : ${errores}"
echo "   Total             : ${total}"
echo "============================================================"
 
# ----------------------------------------------------------------------------
# NOTA sobre sudo sin contrasena:
# En cada maquina destino, crea /etc/sudoers.d/portainer con:
#     admin ALL=(root) NOPASSWD: /usr/bin/docker
# (sustituye 'admin' por tu usuario). Si el usuario ya esta en el grupo
# 'docker', quita el 'sudo' del comando remoto y este paso no hace falta.
# ----------------------------------------------------------------------------
 