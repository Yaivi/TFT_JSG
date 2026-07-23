# Registro Docker privado con TLS, autenticación por token y roles

Documento de referencia del montaje funcional de un registro privado de imágenes
Docker para el laboratorio docente, con cifrado TLS, autenticación de usuarios y
control de acceso por roles (profesor con escritura, alumnos solo lectura).

Recoge la configuración final que funciona, el problema técnico que costó resolver
y su solución, y la prueba de validación de roles.

- **IP del servidor:** `192.168.0.32`
- **Carpeta de trabajo (Windows):** `C:\Users\Usuario\registro`
- **Subcarpeta con certificados y configuración:** `auth\`
- **Puertos:** `5000` (registro), `5001` (servidor de autenticación)

---

## 1. Arquitectura

El sistema se compone de **dos contenedores** que colaboran:

| Contenedor | Imagen | Puerto | Función |
|------------|--------|--------|---------|
| `registro` | `registry:3` | 5000 | Almacena y sirve las imágenes. No autentica por sí mismo: delega en el servidor de tokens. |
| `docker_auth` | `cesanta/docker_auth:1.14.0` | 5001 | Comprueba usuario/contraseña, aplica los permisos (ACL) y emite un token firmado. |

El flujo de un `docker login` o un `docker push/pull` es:

1. El cliente pide acceso al registro (`5000`).
2. El registro responde "necesitas un token, pídelo aquí" (apunta al servidor de auth en `5001`).
3. El cliente se autentica contra `docker_auth` (`5001`), que valida la contraseña, mira la ACL y devuelve un **token firmado** con los permisos del usuario.
4. El cliente presenta el token al registro. El registro **verifica la firma** del token con un certificado de confianza y, si es válido, concede el acceso según los permisos que lleva dentro.

Todo el tráfico (a `5000` y a `5001`) va por HTTPS, usando certificados firmados por una CA propia en la que el cliente confía.

---

## 2. Certificados (resumen de lo que hay en `auth\`)

Tres parejas de certificados, cada una con su función. Se generaron con la imagen
`alpine/openssl`. Esto es un recordatorio de lo que ya está creado; **no hay que
rehacerlo** salvo que se pierdan los ficheros.

| Fichero | Para qué sirve |
|---------|----------------|
| `ca.crt` / `ca.key` | CA propia ("Laboratorio Docker CA"). Es la raíz de confianza: firma el certificado de servidor y el cliente la importa para fiarse de todo el conjunto. |
| `domain.crt` / `domain.key` | Certificado de servidor TLS (con `192.168.0.32` en el campo SAN). Lo usan **tanto** el registro como `docker_auth` para cifrar sus conexiones HTTPS. |
| `auth.crt` / `auth.key` | Pareja **de firma de tokens**. `docker_auth` firma los tokens con `auth.key`; el registro verifica esa firma con `auth.crt`. Es imprescindible que sean pareja (mismo módulo). |

> **Importante:** el registro y `docker_auth` montan la **misma** carpeta `auth\`, así que ambos leen exactamente el mismo `auth.crt`. Eso garantiza que el certificado con el que el registro verifica es el mismo que respalda la clave con la que `docker_auth` firma.

Para confiar en la CA desde Windows (paso necesario una sola vez tras crear la CA):

```powershell
Copy-Item .\domain.crt .\ca.crt -Force

Import-Certificate `
  -FilePath .\ca.crt `
  -CertStoreLocation Cert:\CurrentUser\Root
```

Después se reinicia Docker Desktop para que propague esa confianza a su máquina interna.

---

## 3. El problema que costó resolver y su solución

Durante el montaje, todo parecía correcto (la contraseña se validaba, `docker_auth`
emitía el token, los certificados eran idénticos por SHA-256) y aun así el `docker login`
fallaba con **401** y el registro registraba:

```
failed to verify token: token signed by untrusted key with ID: "PDUG:7APZ:..."
error authorizing context: invalid token
```

### Causa

No era un fallo de configuración ni de certificados, sino un **cambio de ruptura entre
versiones del registro**:

- El registro identifica la clave de firma mediante un **identificador (`kid`)**. El `kid`
  viaja en la cabecera del token y el registro lo busca entre sus claves de confianza.
- **`registry:2`** usaba el formato de identificador antiguo de *libtrust* (la cadena con
  dos puntos: `PDUG:7APZ:...`).
- **`registry:3`** (Distribution 3.x) **eliminó** ese formato y ahora identifica las claves
  por su **JWK Thumbprint (RFC 7638)**, un formato distinto.
- `docker_auth` seguía firmando con el `kid` antiguo de libtrust. Por eso, aunque el
  certificado era el correcto, el registro **no encontraba** ese `kid` entre sus claves de
  confianza y rechazaba el token con "untrusted key". El certificado era idéntico; lo que
  no coincidía era el **formato del identificador de la clave**.

### Solución

`docker_auth` añadió a partir de la versión **1.14.0** una opción que le hace emitir el
`kid` en el formato nuevo (JWK Thumbprint) que `registry:3` entiende:

```yaml
token:
  disable_legacy_key_id: true
```

Con esa única línea (y usando docker_auth ≥ 1.14.0) el `kid` pasa a ser el thumbprint JWK,
el registro lo reconoce contra el mismo `auth.crt` de siempre, y el login funciona. **No
hay que tocar nada en el registro.**

---

## 4. Configuración final que funciona

### `auth\auth_config.yml`

```yaml
server:
  addr: ":5001"
  certificate: "/config/domain.crt"   # certificado TLS del servidor de auth
  key: "/config/domain.key"

token:
  issuer: "Registro Laboratorio"       # debe coincidir con el ISSUER del registro
  expiration: 900                      # validez del token, en segundos
  certificate: "/config/auth.crt"      # certificado de firma de tokens
  key: "/config/auth.key"              # clave con la que se firma
  disable_legacy_key_id: true          # <-- CLAVE: emite el kid en formato JWK (RFC 7638)

users:
  "profesor":
    password: "$2y$05$HASH_DE_PROFESOR"  # hash bcrypt generado con htpasswd
  "alumno":
    password: "$2y$05$HASH_DE_ALUMNO"

acl:
  - match: {account: "profesor"}
    actions: ["*"]                     # profesor: todos los permisos (incluye push)
    comment: "Profesor: acceso total"
  - match: {account: "alumno"}
    actions: ["pull"]                  # alumno: solo lectura
    comment: "Alumno: solo lectura"
```

Los hashes de contraseña se generan así (se copia solo la parte tras los dos puntos):

```powershell
docker run --rm --entrypoint htpasswd httpd:2 -nbB profesor prueba1234
docker run --rm --entrypoint htpasswd httpd:2 -nbB alumno alumno1234
```

### `docker-compose.yml`

```yaml
services:
  auth:
    image: cesanta/docker_auth:1.14.0   # version con soporte para registry 3
    container_name: docker_auth
    restart: always
    command: ["-logtostderr", "/config/auth_config.yml"]  # logs por consola (docker logs)
    ports:
      - "5001:5001"
    volumes:
      - ./auth:/config                  # monta la carpeta auth en /config

  registry:
    image: registry:3
    container_name: registro
    restart: always
    ports:
      - "5000:5000"
    environment:
      REGISTRY_AUTH: token
      REGISTRY_AUTH_TOKEN_REALM: "https://192.168.0.32:5001/auth"  # dónde pedir el token
      REGISTRY_AUTH_TOKEN_SERVICE: "Registro Laboratorio"          # = aud del token
      REGISTRY_AUTH_TOKEN_ISSUER: "Registro Laboratorio"           # = issuer del token
      REGISTRY_AUTH_TOKEN_ROOTCERTBUNDLE: /auth/auth.crt           # con qué verifica la firma
      REGISTRY_HTTP_TLS_CERTIFICATE: /auth/domain.crt              # certificado TLS del registro
      REGISTRY_HTTP_TLS_KEY: /auth/domain.key
    volumes:
      - registro-datos:/data            # almacenamiento persistente de las imágenes
      - ./auth:/auth                    # monta la MISMA carpeta auth en /auth
    depends_on:
      - auth

volumes:
  registro-datos:
```

> Fíjate en que `realm`, `service`/`issuer` y `ROOTCERTBUNDLE` del registro deben encajar
> con lo que pone `docker_auth` en el token (`issuer` y `aud`), y que ambos contenedores
> montan la misma carpeta `auth\`.

---

## 5. Aplicar el cambio (lo que se hizo para que funcionara)

Trabajando desde `C:\Users\Usuario\registro`:

**Paso 1 — Fijar la versión de docker_auth a 1.14.0 y descargarla.**
Asegura que se dispone de la opción `disable_legacy_key_id`.

```powershell
docker compose pull auth
```

**Paso 2 — Añadir `disable_legacy_key_id: true`** bajo `token:` en `auth\auth_config.yml`
(ver configuración del apartado 4). El registro no se toca.

**Paso 3 — Recrear los contenedores** para que relean la configuración y los certificados:

```powershell
docker compose down
docker compose up -d --force-recreate
```

**Paso 4 — Comprobar que docker_auth arrancó bien:**

```powershell
docker logs docker_auth --tail 10
```

Debe mostrar `Config from /config/auth_config.yml (2 users, ...)` y `Serving on :5001`,
sin errores.

**Paso 5 — Iniciar sesión:**

```powershell
docker login 192.168.0.32:5000
```

Con `profesor` / `prueba1234` debe responder **`Login Succeeded`**.

---

## 6. Prueba de validación de roles (profesor y alumno)

Esta prueba demuestra que el control de acceso por roles funciona: el profesor puede
**subir** imágenes y el alumno **solo puede descargarlas**.

### Como profesor (debe poder subir)

```powershell
docker pull hello-world                          # imagen pequeña de prueba (desde Docker Hub)
docker tag hello-world 192.168.0.32:5000/prueba:1  # la renombra apuntando a nuestro registro
docker push 192.168.0.32:5000/prueba:1           # la sube: DEBE funcionar
docker images
docker rmi 192.168.0.32:5000/prueba:1
docker images

```

- `docker pull hello-world`: descarga una imagen mínima para tener algo que subir.
- `docker tag ...`: le pone una etiqueta con la dirección de nuestro registro, que es lo
  que indica a Docker a dónde enviarla.
- `docker push ...`: la sube al registro. Como el profesor tiene `actions: ["*"]`, el push
  **se permite**.

### Como alumno (debe poder leer, pero no escribir)

```powershell
docker logout 192.168.0.32:5000                  # cierra la sesión del profesor
docker login 192.168.0.32:5000                   # entra como: alumno / alumno1234

docker images
docker pull 192.168.0.32:5000/prueba:1           # descarga: DEBE funcionar (lectura)
docker push 192.168.0.32:5000/prueba:1           # subir: DEBE SER DENEGADO

```

- `docker logout`: borra las credenciales guardadas del profesor para ese registro.
- `docker login` (alumno): inicia sesión con el usuario de solo lectura.
- `docker pull ...`: descarga la imagen. Como el alumno tiene `actions: ["pull"]`, **se permite**.
- `docker push ...`: intento de subida. Al no tener permiso de escritura, el registro
  responde con un error de **denegación** (`denied` / `unauthorized`). **Que falle aquí es
  el resultado correcto**: confirma que los alumnos no pueden modificar el repositorio.

### Resultado esperado

| Acción | Profesor | Alumno |
|--------|----------|--------|
| `docker login` | ✅ correcto | ✅ correcto |
| `docker pull` (lectura) | ✅ permitido | ✅ permitido |
| `docker push` (escritura) | ✅ permitido | ❌ **denegado** (correcto) |

Si se obtiene este comportamiento, el módulo del repositorio queda **completo**: privado, cifrado con TLS, con autenticación de usuarios y control de acceso por roles diferenciados.

---

## 7. Comandos útiles de diagnóstico

```powershell
# Ver el reto de autenticación del registro (debe indicar Bearer realm=.../5001/auth)
curl.exe -k -i https://192.168.0.32:5000/v2/

# Logs en vivo
docker logs docker_auth --tail 20
docker logs registro --tail 20

# Comprobar que el certificado de firma y su clave son pareja (mismo Modulus=)
docker run --rm -v ${PWD}\auth:/work -w /work alpine/openssl rsa  -noout -modulus -in auth.key
docker run --rm -v ${PWD}\auth:/work -w /work alpine/openssl x509 -noout -modulus -in auth.crt

# Confirmar que registro y docker_auth leen el MISMO auth.crt (mismo SHA-256)
docker exec registro    sha256sum /auth/auth.crt
docker exec docker_auth sha256sum /config/auth.crt
```

### Interpretación rápida de errores vistos durante el montaje

| Mensaje | Significado | Solución |
|---------|-------------|----------|
| `http://...:5000` + `400 Bad Request` | El cliente habla HTTP contra un servidor HTTPS | Quitar `192.168.0.32:5000` de `insecure-registries` en Docker Engine |
| `token signed by untrusted key with ID` | El `kid` del token no coincide con el formato que espera el registro | `disable_legacy_key_id: true` + docker_auth ≥ 1.14.0 |
| `x509 / unknown authority` | El cliente no confía en la CA | Importar `ca.crt` y reiniciar Docker Desktop |
| `insufficient scope` | El token es válido, pero al usuario le falta permiso | Ajustar la ACL en `auth_config.yml` (esto sería un éxito de firma) |
