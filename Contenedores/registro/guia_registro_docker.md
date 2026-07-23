# Guía completa: registro de imágenes privado con `registry` (Docker)

Registro de imágenes propio para el laboratorio docente, con la imagen oficial `registry` (CNCF Distribution) sobre Docker Desktop en Windows.

## Índice

1. Preparar el registro
2. Acceso desde otros equipos (clientes)
3. Gestión de usuarios
4. Permisos diferenciados: limitación y opciones
5. Limitaciones para la memoria

## 1. Preparar el registro
> **Requisito previo:** Docker Desktop arrancado (la ballena en verde).

### 1.1 Estructura del proyecto
```powershell
mkdir registro
cd registro
mkdir auth
```

### 1.2 Crear el primer usuario (autenticación básica, formato bcrypt)
```powershell
docker run --rm --entrypoint htpasswd httpd:2 -Bbn profesor TuPasswordSeguro | Set-Content -Encoding ASCII auth\htpasswd
```

> El `-Encoding ASCII` es **imprescindible** en Windows; con la codificación por defecto de PowerShell la autenticación falla.

### 1.3 Crear el `docker-compose.yml`
```yaml
services:
  registry:
    image: registry:3
    container_name: registro
    restart: always
    ports:
      - "5000:5000"
    environment:
      REGISTRY_STORAGE_FILESYSTEM_ROOTDIRECTORY: /data
      REGISTRY_STORAGE_DELETE_ENABLED: "true"
      REGISTRY_AUTH: htpasswd
      REGISTRY_AUTH_HTPASSWD_REALM: "Registro Laboratorio"
      REGISTRY_AUTH_HTPASSWD_PATH: /auth/htpasswd
    volumes:
      - registro-datos:/data
      - ./auth:/auth

volumes:
  registro-datos:
```

### 1.4 Arrancar y validar en local
```powershell
docker compose up -d
docker compose ps

docker login localhost:5000
docker tag hello-world localhost:5000/pruebas/hello-world:v1
docker push localhost:5000/pruebas/hello-world:v1
curl.exe -u profesor:TuPasswordSeguro http://localhost:5000/v2/_catalog
```

Si devuelve `{"repositories":["pruebas/hello-world"]}`, el registro funciona.

### 1.5 Verificar la persistencia
```powershell
docker compose restart
curl.exe -u profesor:TuPasswordSeguro http://localhost:5000/v2/_catalog
```

Si la imagen sigue listada tras reiniciar, el volumen persiste los datos.

---

## 2. Acceso desde otros equipos (clientes)
### 2.1 Averiguar la IP del servidor
```powershell
ipconfig
```

Usa la IPv4 del adaptador **"Ethernet"/"Wi-Fi" real** (el conectado al router,
normalmente `192.168.x.x`), **NO** la de los adaptadores virtuales
Hyper-V/vEthernet/WSL.

### 2.2 Declarar el registro como inseguro (HTTP) en CADA cliente
En el equipo cliente: Docker Desktop -> Settings -> Docker Engine. Añade la clave `insecure-registries` **sin borrar lo demás** (ojo a la coma antes de la nueva clave):

```json
{
  "builder": { "gc": { "defaultKeepStorage": "20GB", "enabled": true } },
  "experimental": false,
  "insecure-registries": ["192.168.0.32:5000"]
}
```

Apply & Restart.

### 2.3 Probar desde el cliente

```powershell
docker login 192.168.0.32:5000
docker pull 192.168.0.32:5000/pruebas/hello-world:v1
```

`Login Succeeded` + `Pull complete` = acceso remoto validado.

### 2.4 Si el cliente no conecta

- Abre el puerto **TCP 5000** en el **firewall de Windows** del servidor (regla
  de entrada).
- Asegúrate de que ambos equipos están en la **misma red**.

---

## 3. Gestión de usuarios

Para **añadir** más usuarios, agrega entradas al mismo archivo `auth\htpasswd`.
Usa `Add-Content` (añade) y **no** `Set-Content` (sobrescribiría el archivo):

```powershell
docker run --rm --entrypoint htpasswd httpd:2 -Bbn alumno1 PasswordAlumno1 | Add-Content -Encoding ASCII auth\htpasswd
```

Repite para cada usuario. Después, recarga el registro para que lea el archivo
actualizado:

```powershell
docker compose restart
```

Para **eliminar** un usuario, borra su línea del archivo `auth\htpasswd` y
reinicia el registro.

---

## 4. Permisos diferenciados: limitación y opciones

**Importante:** el `registry` oficial **no** distingue permisos por usuario. Con autenticación htpasswd, **todos los usuarios autenticados pueden leer Y escribir** por igual. No existe de forma nativa el esquema "profesor sube / alumno solo descarga".

Para conseguir permisos diferenciados, manteniéndote en el enfoque de contenedores, hay dos caminos:

- **`docker_auth` (servidor de tokens):** un contenedor adicional
  (`cesanta/docker_auth`) que añade control de acceso por usuario, repositorio y
  acción (pull/push) mediante reglas ACL. El registro delega la autenticación en
  él (`REGISTRY_AUTH=token`). Requiere generar un certificado para firmar los
  tokens. Es la opción ligera para tener control de acceso por roles sin Harbor.
---

