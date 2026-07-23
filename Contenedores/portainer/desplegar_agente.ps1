<#
=============================================================================
  desplegar_agente.ps1
  Propaga el Portainer Agent a un rango de maquinas WINDOWS via OpenSSH.

  Cambio respecto a la version anterior:
    * Levanta el agente con 'docker run' (no 'docker compose'). Es mas robusto
      por SSH: se comporta como un 'docker pull' manual y evita la comprobacion
      previa de imagen de compose, que daba 500 en sesiones SSH no interactivas.
    * Los parametros del agente reflejan docker-compose.agent.yml (imagen,
      puerto, volumen, restart). Si cambias el YAML, espeja aqui esos valores.
    * Muestra el ERROR COMPLETO (antes solo ensenaba la primera linea).

  REQUISITOS:
    * Cliente OpenSSH en este equipo (incluido en Windows 10/11).
    * Servidor OpenSSH ACTIVO en los destinos.
    * Docker Desktop ARRANCADO en los destinos.
    * Para modo desatendido: clave SSH configurada y BatchMode=yes.
      Para probar con contrasena: BatchMode=no (pedira la contrasena por maquina).
    * Despues, abrir el puerto 9001 en el firewall de cada destino.

  USO:  powershell -ExecutionPolicy Bypass -File .\desplegar_agente.ps1
=============================================================================
#>

# ----------------------------- CONFIGURACION --------------------------------
$SshUser   = "labtest"                  # usuario en las maquinas destino
$IpPrefix  = "192.168.0"              # tres primeros octetos de la red
$IpStart   = 40                       # ultimo octeto inicial (incluido)
$IpEnd     = 50                       # ultimo octeto final (incluido)

# Parametros del agente (reflejan docker-compose.agent.yml)
$AgentImage = "portainer/agent:lts"
$AgentPort  = 9001
$AgentName  = "portainer_agent"

$DryRun     = $false                  # $true = solo muestra, no toca nada

# BatchMode=no -> permite contrasena (para pruebas).
# BatchMode=yes -> desatendido, exige clave SSH.
$SshOpts = @(
    "-o","ConnectTimeout=5",
    "-o","BatchMode=no",
    "-o","StrictHostKeyChecking=accept-new"
)
# ----------------------------------------------------------------------------

# Comando remoto, todo en uno:
#   1) borra un agente previo (idempotencia),
#   2) DESCARGA la imagen con 'docker pull' (paso explicito y visible),
#   3) levanta el contenedor con 'docker run'.
# El '&' encadena los tres en cmd (shell por defecto de OpenSSH en Windows);
# cmd devuelve el codigo del ultimo comando (el docker run), que es el que evaluamos.
$RemoteCmd = "docker rm -f $AgentName & docker pull $AgentImage & docker run -d --name $AgentName --restart=always -p ${AgentPort}:${AgentPort} -v /var/run/docker.sock:/var/run/docker.sock $AgentImage"

# Contadores
$ok = 0; $errores = 0; $inaccesibles = 0
$total = $IpEnd - $IpStart + 1

Write-Host "============================================================"
Write-Host " Propagando agente ($AgentImage)"
Write-Host " Rango: $IpPrefix.$IpStart - $IpPrefix.$IpEnd  ($total maquinas)"
if ($DryRun) { Write-Host " *** MODO DRY-RUN: no se ejecuta nada ***" -ForegroundColor Yellow }
Write-Host "============================================================"

foreach ($octeto in $IpStart..$IpEnd) {
    $ip = "$IpPrefix.$octeto"
    Write-Host -NoNewline (" {0,-15} ... " -f $ip)

    if ($DryRun) {
        Write-Host "[DRY-RUN]" -ForegroundColor Yellow
        continue
    }

    # Ejecuta el comando remoto y captura toda la salida
    $salida = ssh $SshOpts "$SshUser@$ip" $RemoteCmd 2>&1
    $code = $LASTEXITCODE

    if ($code -eq 255) {
        Write-Host "[FALLO] inaccesible (apagada, sin OpenSSH o sin clave/contrasena)" -ForegroundColor Red
        $inaccesibles++
    }
    elseif ($code -eq 0) {
        Write-Host "[OK] agente levantado" -ForegroundColor Green
        $ok++
    }
    else {
        Write-Host "[ERROR] (codigo $code) -- salida completa:" -ForegroundColor Red
        $salida | ForEach-Object { Write-Host "        $_" -ForegroundColor DarkYellow }
        $errores++
    }
}

Write-Host "============================================================"
Write-Host " RESUMEN"
Write-Host "   Correctas    : $ok"
Write-Host "   Inaccesibles : $inaccesibles"
Write-Host "   Errores      : $errores"
Write-Host "   Total        : $total"
Write-Host "============================================================"