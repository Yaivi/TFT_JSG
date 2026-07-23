# Chuleta de comandos — Laboratorio k3d (FSO)

**Instalar kubectl y k3d**
```bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
```

**Crear el clúster (1 servidor + 3 nodos) con registro y volumen persistente**
```bash
mkdir -p "$HOME/k3d-datos"
k3d cluster create laboratorio \
  --servers 1 --agents 3 \
  --registry-create laboratorio-registry:0.0.0.0:6001 \
  -p "30000-30050:30000-30050@loadbalancer" \
  --volume "$HOME/k3d-datos:/var/lib/rancher/k3s/storage@all"
```

**Comprobar nodos y etiquetarlos**
```bash
kubectl get nodes -o wide
kubectl label node k3d-laboratorio-agent-0 asignatura=fso
```

**Construir y publicar la imagen FSO en el registro**
```bash
cd ~/ARCHIVOS_DESARROLLO/Dockerfiles/FSO
docker build -t localhost:6001/fso:latest .
docker push localhost:6001/fso:latest
```

**Comprobar qué hay en el registro**
```bash
curl -s http://localhost:6001/v2/_catalog
```

**Dar de alta un alumno (namespace + cuotas + entorno)**
```bash
sed 's/ALUMNO/jsanchez/g' plantilla-alumno.yaml | kubectl apply -f -
sed 's/ALUMNO/jsanchez/g' entorno-alumno.yaml   | kubectl apply -f -
```

**Ver el pod del alumno y en qué nodo cae**
```bash
kubectl get pods -n alumno-jsanchez -o wide
```

**Si sale ImagePullBackOff: importar la imagen a los nodos y reiniciar**
```bash
k3d image import localhost:6001/fso:latest -c laboratorio
kubectl rollout restart deployment/entorno -n alumno-jsanchez
```

**Entrar por SSH y trabajar (contraseña: alumno)**
```bash
ssh alumno@localhost -p 30022
```

**Prueba de persistencia (apagar / encender / comprobar)**
```bash
kubectl scale deployment/entorno -n alumno-jsanchez --replicas=0
kubectl scale deployment/entorno -n alumno-jsanchez --replicas=1
kubectl get pods -n alumno-jsanchez -o wide
ssh alumno@localhost -p 30022 'ls -l ~ && ./hola'
```

**Evidencia de aislamiento y cuotas**
```bash
kubectl describe resourcequota cuota -n alumno-jsanchez
kubectl get all -n alumno-jsanchez
```

**Monitorización básica (uso de CPU/RAM)**
```bash
kubectl top nodes
kubectl top pods -A
```

**Borrar un alumno**
```bash
kubectl delete namespace alumno-jsanchez
```

**Ciclo de vida del clúster (conserva el estado al parar/arrancar)**
```bash
k3d cluster stop laboratorio
k3d cluster start laboratorio
k3d cluster delete laboratorio
```

**Reparar el contexto de kubectl si apunta a localhost:8080**
```bash
k3d kubeconfig merge laboratorio --kubeconfig-switch-context
```
