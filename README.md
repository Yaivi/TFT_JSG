# Laboratorio docente basado en Docker


## Arranque rápido
Aquí se deja una serie de comandos para comprobar que los contenedores creados a partir de las imágenes de los Dockerfiles funcionan todos correctamente

**Asignaturas de un solo contenedor (BD1, BD2, FSO):**

```bash
cd '.\Documents\TRABAJO UNI\Documentos TFG\ARCHIVOS DESARROLLO\Dockerfiles\'

cd BD1\MySql
docker build -t bd1-mysql .
docker run -d --name bd1-mysql -p 3306:3306 bd1-mysql      
docker exec -it bd1-mysql mysql -u alumno -palumno bd1


cd BD1\Oracle
docker build -t bd1-oracle .
docker run -d --name bd1-oracle -p 1521:1521 bd1-oracle
docker exec -it bd1-oracle sqlplus alumno/alumno@//localhost:1521/BD1

cd BD2
docker build -t bd2 .
docker run -it --name bd2 -p 3307:3307 bd2-mysql
docker exec -it bd2 bash

cd FSO
docker build  -t fso .
docker run -dit --name fso fso bash
docker start fso
docker exec -it fso bash

```

**Asignaturas multicontenedor (Redes, ASR):**
```bash
cd RC
docker compose up -d --build
docker exec -it rc-cliente bash
docker exec -it rc-servidor bash
docker exec -it rc-router bash
docker compose down  



cd ASR
docker compose up -d --build
docker exec -it asr-cliente bash
docker exec -it asr-servidor bash
docker exec -it asr-pasarela bash
docker compose down  
```

## Puesta en marcha del laboratorio

Esta parte va dirigida a quien **monta** el laboratorio (profesorado o administración).

### Convenciones

- `<IP_SERVIDOR>` es la IP del equipo que aloja el registro y la pasarela. Sustitúyela
  en todos los comandos por la propia. Comprueba cuál es con `ipconfig` (Windows) o
  `hostname -I` (Linux), y usa la del adaptador **físico**, no la de los adaptadores
  virtuales de Hyper-V, vEthernet o WSL.
- Los ejemplos están en PowerShell porque el desarrollo se hizo sobre Docker Desktop en
  Windows. En Linux funcionan igual cambiando `\` por `/` y `${PWD}\auth` por `$PWD/auth`.
- Requisitos comunes: Docker Engine o Docker Desktop arrancado, y los dos equipos
  (servidor y cliente) en la misma red.

| Componente | Puerto | Para qué |
|---|---|---|
| Registro de imágenes | 5000/tcp | `docker login`, `push`, `pull` |
| Servidor de tokens | 5001/tcp | Emisión de tokens de autorización |
| Pasarela SSH | 2222/tcp | Acceso de los alumnos al modelo centralizado |
| Portainer | 9443/tcp | Consola de monitorización |
| Agente Portainer | 9001/tcp | Solo en máquinas monitorizadas |
| WireGuard | 51820/udp | Túnel de acceso remoto |

Abre esos puertos en el cortafuegos del servidor. El único que debe salir a Internet
(reenvío en el router) es el 51820/udp.

---

### 1. Registro privado de imágenes

Dos contenedores que se reparten el trabajo: `registro` almacena y sirve las imágenes,
y `docker_auth` valida credenciales, aplica los permisos y emite un token firmado. El
registro no maneja contraseñas: solo comprueba la firma del token.

El flujo de cualquier `login`, `push` o `pull` es:

1. El cliente pide acceso al registro (5000).
2. El registro contesta "necesitas un token, pídelo en el 5001".
3. El cliente se autentica contra `docker_auth`, que mira la ACL y firma un token con
   los permisos de ese usuario.
4. El cliente presenta el token; el registro verifica la firma y concede el acceso.

Todo el tráfico va por HTTPS con certificados de una CA propia.

#### 1.1 Certificados

Hacen falta tres parejas dentro de `auth/`:

| Ficheros | Función |
|---|---|
| `ca.crt` / `ca.key` | CA propia. Raíz de confianza: firma el certificado de servidor y es la que importan los clientes. |
| `domain.crt` / `domain.key` | Certificado TLS de servidor, con la IP en el campo SAN. Lo usan los **dos** contenedores. |
| `auth.crt` / `auth.key` | Pareja exclusiva para firmar tokens. `docker_auth` firma con la clave, el registro verifica con el certificado. |

Se parte de una carpeta de trabajo con una subcarpeta `auth`:

```powershell
mkdir registro; cd registro; mkdir auth
```

Primero la CA propia, que será la raíz de confianza de todo el conjunto:

```powershell
docker run --rm -v ${PWD}\auth:/work -w /work alpine/openssl `
  req -x509 -newkey rsa:4096 -nodes -days 3650 `
  -keyout ca.key -out ca.crt -subj "/CN=Laboratorio Docker CA"
```

Después la clave y la petición del certificado de servidor:

```powershell
docker run --rm -v ${PWD}\auth:/work -w /work alpine/openssl `
  req -newkey rsa:4096 -nodes -keyout domain.key -out domain.csr `
  -subj "/CN=<IP_SERVIDOR>"
```

El certificado se firma con la CA incluyendo la IP en el campo SAN. Ese campo es
obligatorio, sin él los clientes actuales rechazan el certificado aunque el nombre común
coincida.

```powershell
"subjectAltName=IP:<IP_SERVIDOR>" | Set-Content -Encoding ASCII auth\san.ext

docker run --rm -v ${PWD}\auth:/work -w /work alpine/openssl `
  x509 -req -in domain.csr -CA ca.crt -CAkey ca.key -CAcreateserial `
  -days 825 -extfile san.ext -out domain.crt
```

Por último la pareja de firma de tokens, que va autofirmada y no necesita pasar por la CA:

```powershell
docker run --rm -v ${PWD}\auth:/work -w /work alpine/openssl `
  req -x509 -newkey rsa:4096 -nodes -days 3650 `
  -keyout auth.key -out auth.crt -subj "/CN=token-signing"
```

Conviene comprobar que `auth.crt` y `auth.key` son pareja. Los dos comandos deben
imprimir el **mismo** `Modulus`; si no coinciden, la verificación de la firma fallará
siempre:

```powershell
docker run --rm -v ${PWD}\auth:/work -w /work alpine/openssl rsa  -noout -modulus -in auth.key
docker run --rm -v ${PWD}\auth:/work -w /work alpine/openssl x509 -noout -modulus -in auth.crt
```

####  1.2 Usuarios y permisos

Los usuarios y las reglas de acceso viven en `auth/auth_config.yml`. Las contraseñas se
guardan como hash bcrypt, nunca en claro:

```powershell
docker run --rm --entrypoint htpasswd httpd:2 -nbB profesor prueba1234
docker run --rm --entrypoint htpasswd httpd:2 -nbB alumno   alumno1234
```

De la salida se copia **solo la parte posterior a los dos puntos**, que empieza por `$2y$`.

```yaml
server:
  addr: ":5001"
  certificate: "/config/domain.crt"
  key: "/config/domain.key"

token:
  issuer: "Registro Laboratorio"
  expiration: 900
  certificate: "/config/auth.crt"
  key: "/config/auth.key"
  disable_legacy_key_id: true

users:
  "profesor":
    password: "$2y$05$..."
  "alumno":
    password: "$2y$05$..."

acl:
  - match: {account: "profesor"}
    actions: ["*"]
    comment: "Profesor: acceso total"
  - match: {account: "alumno"}
    actions: ["pull"]
    comment: "Alumno: solo lectura"
```

El `issuer` debe coincidir exactamente con el que se configura en el registro, y
`expiration` fija la validez del token en segundos. La opción `disable_legacy_key_id` es
imprescindible con `registry:3`.

#### 1.3 Arranque

```yaml
services:
  auth:
    image: cesanta/docker_auth:1.14.0
    container_name: docker_auth
    restart: always
    command: ["-logtostderr", "/config/auth_config.yml"]
    ports:
      - "5001:5001"
    volumes:
      - ./auth:/config

  registry:
    image: registry:3
    container_name: registro
    restart: always
    ports:
      - "5000:5000"
    environment:
      REGISTRY_AUTH: token
      REGISTRY_AUTH_TOKEN_REALM: "https://<IP_SERVIDOR>:5001/auth"
      REGISTRY_AUTH_TOKEN_SERVICE: "Registro Laboratorio"
      REGISTRY_AUTH_TOKEN_ISSUER: "Registro Laboratorio"
      REGISTRY_AUTH_TOKEN_ROOTCERTBUNDLE: /auth/auth.crt
      REGISTRY_HTTP_TLS_CERTIFICATE: /auth/domain.crt
      REGISTRY_HTTP_TLS_KEY: /auth/domain.key
      REGISTRY_STORAGE_FILESYSTEM_ROOTDIRECTORY: /data
      REGISTRY_STORAGE_DELETE_ENABLED: "true"
    volumes:
      - registro-datos:/data
      - ./auth:/auth
    depends_on:
      - auth

volumes:
  registro-datos:
```

`REALM` indica al cliente dónde pedir el token, `SERVICE` e `ISSUER` deben coincidir con
lo que `docker_auth` escribe dentro de cada token, y `ROOTCERTBUNDLE` es el certificado
con el que el registro verifica la firma.

`ROOTDIRECTORY` no es opcional: sin ella `registry:3` escribe en `/var/lib/registry` y el
volumen montado en `/data` queda sin usar, con lo que las imágenes no sobrevivirían a un
`docker compose down`.


```powershell
docker compose up -d
docker logs docker_auth --tail 10
```

El servidor de autenticación debe indicar que ha cargado la configuración con sus dos
usuarios y que está escuchando en el 5001, sin errores.

#### 1.4 Confiar en la CA desde los clientes

Paso obligatorio en **cada** equipo que vaya a usar el registro. Se copia `ca.crt` al
cliente y se importa. En Windows, al almacén de raíces de confianza, reiniciando después
Docker Desktop para que propague la confianza a su máquina interna:

```powershell
Import-Certificate -FilePath .\ca.crt -CertStoreLocation Cert:\CurrentUser\Root
```

En Linux la vía más limpia es acotar la confianza a este registro concreto en lugar de
tocar el almacén del sistema:

```bash
sudo mkdir -p /etc/docker/certs.d/<IP_SERVIDOR>:5000
sudo cp ca.crt /etc/docker/certs.d/<IP_SERVIDOR>:5000/ca.crt
sudo systemctl restart docker
```

Y en macOS, sobre el llavero del sistema:

```bash
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ca.crt
```

**No** añadas el registro a `insecure-registries`, eso era necesario en la primera
versión sobre HTTP y ahora provoca un `400 Bad Request` al hablar HTTP contra HTTPS. 

#### 1.5 Validación de roles

Se prepara una imagen cualquiera para tener algo que subir:

```powershell
docker pull hello-world
docker tag hello-world <IP_SERVIDOR>:5000/prueba:1
```

Como profesor, tanto la subida como la descarga deben completarse:

```powershell
docker logout <IP_SERVIDOR>:5000
docker login  <IP_SERVIDOR>:5000
docker push <IP_SERVIDOR>:5000/prueba:1
docker pull <IP_SERVIDOR>:5000/prueba:1
```

Como alumno, la descarga funciona igual:

```powershell
docker logout <IP_SERVIDOR>:5000
docker login  <IP_SERVIDOR>:5000
docker pull <IP_SERVIDOR>:5000/prueba:1
```

Pero la subida debe rechazarse. Se emplea a propósito una imagen que aún no está en el
registro: reenviar una ya existente podría resolverse sin escribir nada y la prueba no
demostraría gran cosa.

```powershell
docker pull alpine
docker tag alpine <IP_SERVIDOR>:5000/test-alumno:1
docker push <IP_SERVIDOR>:5000/test-alumno:1
```

Sin sesión iniciada, cualquier operación debe exigir autenticación:

```powershell
docker logout <IP_SERVIDOR>:5000
docker pull <IP_SERVIDOR>:5000/prueba:1
```

| Acción | Profesor | Alumno | Sin sesión |
|---|---|---|---|
| `docker login` | correcto | correcto | — |
| `docker pull` | permitido | permitido | denegado |
| `docker push` | permitido | **denegado** | denegado |

Que el `push` del alumno falle con `denied: requested access to the resource is denied`
es el **resultado correcto** de la prueba.

Para comprobar la persistencia se recrean los contenedores y la imagen debe seguir
listada. Si desaparece, revisa `ROOTDIRECTORY` en el apartado 1.3:

```powershell
docker compose down
docker compose up -d
```

#### 1.6 Errores frecuentes

| Mensaje | Qué pasa | Solución |
|---|---|---|
| `token signed by untrusted key with ID: "ABCD:1234:..."` | `registry:3` identifica las claves por su JWK Thumbprint (RFC 7638); `registry:2` usaba el formato antiguo de *libtrust*, que es el de la cadena con dos puntos. Si `docker_auth` firma con el `kid` antiguo, el registro no lo encuentra entre sus claves aunque el certificado sea el correcto. | `disable_legacy_key_id: true` y `docker_auth` ≥ 1.14.0. En el registro no se toca nada. |
| `400 Bad Request` sobre `http://...:5000` | El cliente habla HTTP contra un servidor HTTPS | Quitar el registro de `insecure-registries` |
| `x509: certificate signed by unknown authority` | El cliente no confía en la CA | Importar `ca.crt` (apartado 1.4) y reiniciar Docker |
| `insufficient scope` | El token es válido pero al usuario le falta permiso | Ajustar la ACL. Es señal de que la firma funciona. |
| Login correcto pero el catálogo aparece vacío tras recrear | El volumen no se está usando | Añadir `ROOTDIRECTORY` (apartado 1.3) |

#### 1.8 Publicar y versionar imágenes de asignatura

```powershell
docker login <IP_SERVIDOR>:5000
docker build -t <IP_SERVIDOR>:5000/asr-servidor:1.0 .
docker push  <IP_SERVIDOR>:5000/asr-servidor:1.0
```

Para dejar preparado un estado concreto de una práctica, por ejemplo el servidor de ASR
con el DNS ya configurado, se consolida el contenedor en una imagen nueva y se publica
con su propia etiqueta:

```powershell
docker commit asr-servidor-1 <IP_SERVIDOR>:5000/asr-servidor:practica-dns
docker push <IP_SERVIDOR>:5000/asr-servidor:practica-dns
```

Etiqueta siempre con versión. Evita `latest` para el material docente: no permite volver
atrás si una actualización rompe algo.

---

### 2. Pasarela de acceso y alta de usuarios

La pasarela es el único punto de entrada al modelo centralizado. Monta el socket de
Docker del anfitrión, así que las órdenes que se ejecutan dentro actúan sobre el Docker
real. Por eso los alumnos **no** entran en el grupo `docker` ni tienen `sudo` general:
se les autorizan comandos concretos sobre contenedores concretos mediante reglas
`sudoers` generadas por usuario.

```powershell
cd gateway
docker build -t lab-gateway .
docker run -d --name lab-gateway -p 2222:22 `
  -v /var/run/docker.sock:/var/run/docker.sock lab-gateway
```

El alta de un usuario y el despliegue de su puesto se hacen con los scripts de
aprovisionamiento. El segundo argumento de `usuario_nuevo.sh` es el rol, y por defecto
es `alumno`:

```bash
./usuario_nuevo.sh alumno01
./usuario_nuevo.sh prof_ana profesor
./dar_asignatura.sh alumno01 rc
```

`dar_asignatura.sh` usa `docker compose create` en lugar de `up`, el administrador crea
el puesto, el alumno lo arranca. Cada despliegue recibe un octeto propio para que las
subredes de distintos alumnos no colisionen.

#### Validación

Una sesión de trabajo completa desde la cuenta de un alumno debe poder ejecutarse sin
manipular imágenes, redes ni ficheros de composición:

```bash
ssh alumno01@<IP_SERVIDOR> -p 2222

sudo docker ps -a --filter name=^alumno01-
sudo docker compose -p alumno01-rc start
sudo docker exec -it alumno01-rc-router-1 bash
exit
sudo docker compose -p alumno01-rc stop
```

Y estas otras deben fallar todas, que es lo que demuestra que el modelo de permisos
sirve de algo: acceso directo al demonio, ver o tocar puestos ajenos, crear contenedores
nuevos y escapar al anfitrión.

```bash
docker ps
sudo docker ps -a
sudo docker compose -p alumno01-rc up -d
sudo docker start alumno02-rc-cliente-1
sudo docker run -v /:/host -it alpine sh
```

---

### 3. Monitorización con Portainer

El servidor detecta por sí solo el Docker local, así que en el modelo centralizado no
hace falta ningún agente: ya ve todos los contenedores de los alumnos. El agente solo se
despliega en las máquinas **adicionales** que se quieran vigilar, es decir, los equipos
de laboratorio que trabajen en modelo distribuido.

Servidor:

```yaml
services:
  portainer:
    image: portainer/portainer-ce:lts
    container_name: portainer
    restart: always
    ports: ["9443:9443"]
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - portainer_data:/data
volumes:
  portainer_data:
```

Agente, solo en las máquinas remotas:

```yaml
services:
  portainer_agent:
    image: portainer/agent:lts
    container_name: portainer_agent
    restart: always
    ports: ["9001:9001"]
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /var/lib/docker/volumes:/var/lib/docker/volumes
```

Primer acceso en `https://<IP_SERVIDOR>:9443` para crear la cuenta de administrador.
Cada máquina con agente se da de alta en *Environments → Add environment → Docker
Standalone → Agent*, indicando `<IP_PUESTO>:9001`.

Para desplegar el agente en varios equipos a la vez están los scripts de propagación
(`propagar-linux.sh` y `propagar-windows.ps1`), que recorren un rango de IPs. Requieren
acceso SSH por clave y, en Windows, el servidor OpenSSH activo en los destinos.

---

### 4. Acceso remoto por VPN

`wg-easy` y la pasarela comparten red de Docker, de modo que el cliente conectado al
túnel alcanza la pasarela contenedor a contenedor. Al exterior solo se expone el
51820/udp; el SSH nunca atraviesa un puerto del anfitrión.

La contraseña del panel se guarda como hash, que se genera con la utilidad incluida en
la propia imagen:

```powershell
docker run --rm ghcr.io/wg-easy/wg-easy:14 wgpw TuPasswordDelPanel
```

En el `docker-compose.yml` del módulo hay que rellenar `WG_HOST`, con la IP pública o el
dominio, y `PASSWORD_HASH`, duplicando cada `$` del hash obtenido. Después:

```powershell
docker compose up -d --build
```

El panel queda en `http://localhost:51821`, y desde ahí se crea el perfil del alumno y se
descarga su fichero `.conf`. El alumno lo importa en la aplicación de WireGuard, activa
el túnel y ya puede conectar:

```bash
ssh alumno01@172.28.0.3
```

En el router hace falta reenviar el **51820/udp** hacia el servidor, en UDP y no en TCP,
y conviene reservarle la IP por DHCP estático. Comprueba también que la conexión tiene IP
pública alcanzable y no está detrás de CGNAT.

#### Validación

| Prueba desde una red externa | Resultado esperado |
|---|---|
| SSH a `172.28.0.3` con el túnel activo | accesible |
| SSH a `172.28.0.3` sin túnel | bloqueado |
| SSH directo a la IP pública, puerto 22 | bloqueado |
| Panel en la IP pública, puerto 51821 | bloqueado |

---


# Validaciones Dockerfiles para prácticas
Aquí se muestra la serie de comandos que se han usado en los contenedores de cada asignatura 
para comprobar si es posible realizar las prácticas de estas en los contenedores.

## BD1 oracle
### Arrancar el servicio y conectar
 
```bash
sudo service oracle-xe start   # o el nombre del servicio según la imagen
lsnrctl status                  # comprobar que el listener está activo
sqlplus sys/tu_password AS SYSDBA
```
 
Conexión normal como usuario de prácticas:
 
```bash
sqlplus alumno/clave@//localhost:1521/XEPDB1
```
 
### Crear esquema y tablas con restricciones de integridad
 
```sql
CREATE TABLE autores (
  id NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  nombre VARCHAR2(60) NOT NULL,
  nacionalidad VARCHAR2(40)
);
 
CREATE TABLE libros (
  id NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  titulo VARCHAR2(100) NOT NULL,
  autor_id NUMBER NOT NULL,
  anio NUMBER CHECK (anio > 1400),
  isbn VARCHAR2(20) UNIQUE,
  CONSTRAINT fk_autor FOREIGN KEY (autor_id) REFERENCES autores(id)
    ON DELETE CASCADE
);
```
 
Comprobar la estructura:
 
```sql
DESCRIBE libros;
SELECT table_name FROM user_tables;
SELECT constraint_name, constraint_type FROM user_constraints WHERE table_name = 'LIBROS';
```
 
### Probar restricciones de integridad
 
```sql
-- Debe fallar: FK inexistente
INSERT INTO libros (titulo, autor_id, anio) VALUES ('Libro fantasma', 999, 2020);
 
INSERT INTO autores (nombre) VALUES ('Cervantes');
COMMIT;
 
-- Debe fallar: CHECK
INSERT INTO libros (titulo, autor_id, anio) VALUES ('Libro viejo', 1, 1200);
 
-- Debe funcionar
INSERT INTO libros (titulo, autor_id, anio, isbn) VALUES ('Don Quijote', 1, 1605, 'ISBN-001');
COMMIT;
 
-- Debe fallar: UNIQUE duplicado
INSERT INTO libros (titulo, autor_id, anio, isbn) VALUES ('Otro libro', 1, 1610, 'ISBN-001');
 
-- Probar ON DELETE CASCADE
DELETE FROM autores WHERE nombre = 'Cervantes';
COMMIT;
SELECT * FROM libros;  -- el libro asociado debe haber desaparecido
```
 
### Consultas (SELECT)
 
```sql
INSERT INTO autores (nombre, nacionalidad) VALUES ('García Márquez', 'Colombia');
INSERT INTO autores (nombre, nacionalidad) VALUES ('Orwell', 'Reino Unido');
COMMIT;
 
INSERT INTO libros (titulo, autor_id, anio, isbn)
  SELECT 'Cien años de soledad', id, 1967, 'ISBN-002' FROM autores WHERE nombre = 'García Márquez';
INSERT INTO libros (titulo, autor_id, anio, isbn)
  SELECT '1984', id, 1949, 'ISBN-003' FROM autores WHERE nombre = 'Orwell';
COMMIT;
 
-- Consulta simple
SELECT titulo, anio FROM libros WHERE anio > 1950;
 
-- Join
SELECT l.titulo, a.nombre, a.nacionalidad
FROM libros l JOIN autores a ON l.autor_id = a.id;
 
-- Agregación
SELECT a.nombre, COUNT(*) AS num_libros
FROM libros l JOIN autores a ON l.autor_id = a.id
GROUP BY a.nombre
HAVING COUNT(*) >= 1;
 
-- Subconsulta
SELECT titulo FROM libros
WHERE autor_id = (SELECT id FROM autores WHERE nombre = 'Orwell');
```
 
### Operaciones de modificación de datos (DML)
 
```sql
UPDATE libros SET anio = 1948 WHERE titulo = '1984';
COMMIT;
 
DELETE FROM libros WHERE titulo = 'Cien años de soledad';
COMMIT;
 
SELECT * FROM libros;
```
 
###  Comprobación final de estado
 
```sql
SELECT table_name FROM user_tables;
SELECT COUNT(*) FROM libros;
SELECT * FROM user_users;   -- ver el usuario/esquema actual
```


## BD1 mysql
### Arrancar el servicio y conectar
 
```bash
sudo service mysql start
sudo service mysql status
sudo mysql -u root
```
 
### Crear esquema y tablas con restricciones de integridad
 
```sql
CREATE DATABASE biblioteca;
USE biblioteca;
 
CREATE TABLE autores (
  id INT AUTO_INCREMENT PRIMARY KEY,
  nombre VARCHAR(60) NOT NULL,
  nacionalidad VARCHAR(40)
);
 
CREATE TABLE libros (
  id INT AUTO_INCREMENT PRIMARY KEY,
  titulo VARCHAR(100) NOT NULL,
  autor_id INT NOT NULL,
  anio INT CHECK (anio > 1400),
  isbn VARCHAR(20) UNIQUE,
  FOREIGN KEY (autor_id) REFERENCES autores(id)
    ON DELETE CASCADE
    ON UPDATE CASCADE
);
```
 
Comprobar que se creó bien:
 
```sql
SHOW TABLES;
DESCRIBE libros;
SHOW CREATE TABLE libros;
```
 
### Probar restricciones de integridad
 
```sql
-- Debe fallar: autor_id no existe (violación de FK)
INSERT INTO libros (titulo, autor_id, anio) VALUES ('Libro fantasma', 999, 2020);
 
-- Debe fallar: anio no cumple el CHECK
INSERT INTO autores (nombre) VALUES ('Cervantes');
INSERT INTO libros (titulo, autor_id, anio) VALUES ('Libro viejo', 1, 1200);
 
-- Debe funcionar
INSERT INTO libros (titulo, autor_id, anio, isbn) VALUES ('Don Quijote', 1, 1605, 'ISBN-001');
 
-- Probar UNIQUE: debe fallar (isbn repetido)
INSERT INTO libros (titulo, autor_id, anio, isbn) VALUES ('Otro libro', 1, 1610, 'ISBN-001');
 
-- Probar ON DELETE CASCADE
DELETE FROM autores WHERE id = 1;
SELECT * FROM libros;  -- el libro asociado también debe haberse borrado
```
 
### Consultas (SELECT)
 
```sql
INSERT INTO autores (nombre, nacionalidad) VALUES ('García Márquez', 'Colombia'), ('Orwell', 'Reino Unido');
INSERT INTO libros (titulo, autor_id, anio, isbn) VALUES
  ('Cien años de soledad', 1, 1967, 'ISBN-002'),
  ('1984', 2, 1949, 'ISBN-003'),
  ('Rebelión en la granja', 2, 1945, 'ISBN-004');
 
-- Consulta simple
SELECT titulo, anio FROM libros WHERE anio > 1950;
 
-- Join
SELECT l.titulo, a.nombre, a.nacionalidad
FROM libros l
JOIN autores a ON l.autor_id = a.id;
 
-- Agregación
SELECT a.nombre, COUNT(*) AS num_libros
FROM libros l JOIN autores a ON l.autor_id = a.id
GROUP BY a.nombre
HAVING COUNT(*) >= 1;
 
-- Subconsulta
SELECT titulo FROM libros
WHERE autor_id = (SELECT id FROM autores WHERE nombre = 'Orwell');
```
 
### Operaciones de modificación de datos (DML)
 
```sql
UPDATE libros SET anio = 1948 WHERE titulo = '1984';
DELETE FROM libros WHERE titulo = 'Rebelión en la granja';
SELECT * FROM libros;
```
 
### Comprobación final de estado
 
```sql
SHOW DATABASES;
SHOW TABLES FROM biblioteca;
SELECT COUNT(*) FROM libros;
```


## BD2
### Tablas y espacio en disco (diseño físico)
 
```sql
CREATE DATABASE bd2_test;
USE bd2_test;
 
CREATE TABLE alumnos (
  id INT AUTO_INCREMENT PRIMARY KEY,
  nombre VARCHAR(50),
  nota DECIMAL(4,2)
);
```
 
```bash
sudo ls -lh /var/lib/mysql/bd2_test/
```
 
```sql
SELECT table_name, data_length, index_length, data_free
FROM information_schema.tables
WHERE table_schema = 'bd2_test';
 
OPTIMIZE TABLE alumnos;
```

### Usuarios y permisos

```sql
CREATE USER 'alumno1'@'%' IDENTIFIED BY 'clave123';
GRANT SELECT, INSERT ON bd2_test.* TO 'alumno1'@'%';
FLUSH PRIVILEGES;
SHOW GRANTS FOR 'alumno1'@'%';
REVOKE INSERT ON bd2_test.* FROM 'alumno1'@'%';
```
 
Desde otra sesión, conectando como ese usuario:
 
```bash
mysql -u alumno1 -p bd2_test
```
 
```sql
INSERT INTO alumnos (nombre, nota) VALUES ('Test', 5.0);  -- debe fallar tras el REVOKE
SELECT * FROM alumnos;                                     -- debe funcionar
```


 
### Copias de seguridad y recuperación
 
```bash
mysqldump -u root -p bd2_test > /tmp/backup_bd2test.sql
```
```sql
DROP DATABASE bd2_test;
```
```bash
mysql -u root -p -e "CREATE DATABASE bd2_test;"
mysql -u root -p bd2_test < /tmp/backup_bd2test.sql
```
```sql
SELECT * FROM alumnos;   -- comprobar que volvieron los datos
``` 
```bash
sudo service mysql stop
sudo tar -czvf /tmp/datadir_backup.tar.gz /var/lib/mysql
sudo service mysql start
```

### Triggers y procedimientos almacenados
 
```sql
CREATE TABLE log_cambios (
  id INT AUTO_INCREMENT PRIMARY KEY,
  mensaje VARCHAR(100),
  fecha TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
 
DELIMITER //
CREATE TRIGGER trg_alumnos_update
AFTER UPDATE ON alumnos
FOR EACH ROW
BEGIN
  INSERT INTO log_cambios (mensaje)
  VALUES (CONCAT('Alumno ', OLD.id, ' cambió nota de ', OLD.nota, ' a ', NEW.nota));
END //
DELIMITER ;
 
UPDATE alumnos SET nota = 7.0 WHERE id = 1;
SELECT * FROM log_cambios;   -- debe aparecer una fila nueva
```
 
```sql
DELIMITER //
CREATE PROCEDURE aprobar_alumno(IN alumno_id INT)
BEGIN
  UPDATE alumnos SET nota = 5.0 WHERE id = alumno_id AND nota < 5.0;
END //
DELIMITER ;
 
CALL aprobar_alumno(1);
```



## FSO
### Herramientas de desarrollo disponibles
 
```bash
gcc --version
gdb --version
make --version
man gcc          # comprobar que las páginas de manual están instaladas
```
 
### Compilación básica en C (memoria, arrays, punteros)
 
```bash
mkdir -p ~/fso_test && cd ~/fso_test
cat > memoria.c << 'EOF'
#include <stdio.h>
#include <stdlib.h>
 
int main() {
    int *array = malloc(5 * sizeof(int));
    if (array == NULL) { perror("malloc"); return 1; }
    for (int i = 0; i < 5; i++) array[i] = i * i;
    for (int i = 0; i < 5; i++) printf("array[%d] = %d\n", i, array[i]);
    free(array);
    return 0;
}
EOF
gcc -Wall -o memoria memoria.c
./memoria
```
 
Comprobar fugas de memoria (si tenéis valgrind en la imagen):
 
```bash
valgrind --leak-check=full ./memoria
```
 
### Procesos: fork(), exec(), espera no bloqueante
 
```bash
cat > procesos.c << 'EOF'
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/wait.h>
 
int main() {
    pid_t pid = fork();
    if (pid < 0) { perror("fork"); return 1; }
    if (pid == 0) {
        printf("Hijo (pid=%d) ejecutando 'echo hola desde exec'\n", getpid());
        execlp("echo", "echo", "hola desde exec", NULL);
        perror("execlp");
        _exit(1);
    } else {
        int status;
        pid_t r;
        // Espera no bloqueante: sondear hasta que el hijo termine
        do {
            r = waitpid(pid, &status, WNOHANG);
            if (r == 0) { printf("Padre: hijo %d aún no termina...\n", pid); sleep(1); }
        } while (r == 0);
        printf("Padre: hijo %d terminó con estado %d\n", pid, WEXITSTATUS(status));
    }
    return 0;
}
EOF
gcc -Wall -o procesos procesos.c
./procesos
```
 
### Ficheros: llamadas al sistema (open/read/write/close) y permisos
 
```bash
cat > ficheros.c << 'EOF'
#include <stdio.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>
 
size_t strlen_manual(const char *s);   // prototipo declarado antes de usarla
 
int main() {
    int fd = open("estado.dat", O_CREAT | O_WRONLY | O_TRUNC, 0644);
    if (fd < 0) {
        perror("open");
        return 1;
    }
    const char *datos = "sala=1;asientos=50\n";
    write(fd, datos, strlen_manual(datos));
    close(fd);
 
    fd = open("estado.dat", O_RDONLY);
    if (fd < 0) {
        perror("open");
        return 1;
    }
    char buf[100];
    ssize_t n = read(fd, buf, sizeof(buf) - 1);
    if (n >= 0) {
        buf[n] = '\0';
        printf("Contenido leído: %s", buf);
    }
    close(fd);
    return 0;
}
 
size_t strlen_manual(const char *s) {
    size_t len = 0;
    while (s[len]) len++;
    return len;
}
EOF
gcc -Wall -o ficheros ficheros.c
./ficheros
ls -l estado.dat
chmod 600 estado.dat
ls -l estado.dat   # comprobar que el cambio de permisos se refleja
cat estado.dat
```

### Hilos con pthread: mutex y variables de condición
 
```bash
cat > hilos.c << 'EOF'
#include <stdio.h>
#include <pthread.h>
#include <unistd.h>
 
int asientos_libres = 3;
pthread_mutex_t mutex = PTHREAD_MUTEX_INITIALIZER;
pthread_cond_t cond = PTHREAD_COND_INITIALIZER;
 
void *reservar(void *arg) {
    pthread_mutex_lock(&mutex);
    while (asientos_libres <= 0) {
        printf("Hilo %ld: esperando asiento libre...\n", (long)arg);
        pthread_cond_wait(&cond, &mutex);
    }
    asientos_libres--;
    printf("Hilo %ld: reservó un asiento (quedan %d)\n", (long)arg, asientos_libres);
    pthread_mutex_unlock(&mutex);
    return NULL;
}
 
void *liberar(void *arg) {
    sleep(1);
    pthread_mutex_lock(&mutex);
    asientos_libres++;
    printf("Hilo %ld: liberó un asiento (quedan %d)\n", (long)arg, asientos_libres);
    pthread_cond_signal(&cond);
    pthread_mutex_unlock(&mutex);
    return NULL;
}
 
int main() {
    pthread_t t1, t2, t3, t4;
    pthread_create(&t1, NULL, reservar, (void *)1);
    pthread_create(&t2, NULL, reservar, (void *)2);
    pthread_create(&t3, NULL, reservar, (void *)3);
    pthread_create(&t4, NULL, reservar, (void *)4);  // este debe esperar
 
    pthread_t tl;
    pthread_create(&tl, NULL, liberar, (void *)99);
 
    pthread_join(t1, NULL); pthread_join(t2, NULL);
    pthread_join(t3, NULL); pthread_join(t4, NULL);
    pthread_join(tl, NULL);
    return 0;
}
EOF
gcc -Wall -pthread -o hilos hilos.c
./hilos
```
 

## RC cliente
### Comprobar direcciones y enrutamiento
```bash
ip a
ip route
hostname
```
### Conectividad router
```bash
ping -c 3 10.${OCTETO}.1.254
```
### Conectividad servidor
 
```bash
ping -c 3 10.${OCTETO}.2.10
traceroute 10.${OCTETO}.2.10
```

## RC servidor
### Comprobar direcciones y enrutamiento
```bash
ip a                                    # debe verse 10.${OCTETO}.2.10/24
ip route                                # debe existir ruta hacia 10.${OCTETO}.1.0/24 vía 10.${OCTETO}.2.254
hostname                                # redes-servidor
```
 
### Conectividad router y cliente a través de router 
```bash
ping -c 3 10.${OCTETO}.2.254
ping -c 3 10.${OCTETO}.1.10
traceroute 10.${OCTETO}.1.10
```
 

## ASR
```bash
ip a                                    # debe verse solo 10.${OCTETO}.2.10/24
hostname                                # asr-servidor
ip route                                # la puerta de enlace debe ser 10.${OCTETO}.2.254 (pasarela)
```
 
### DNS (BIND)
```bash
named-checkconf /etc/bind/named.conf
rndc status
dig @localhost servidor.vuestrodominio
dig @localhost -x 10.2.2.10
```
 
### Correo — Postfix
 
```bash
ss -tlnp | grep :25
tail -f /var/log/mail.log &
```
 
Prueba de envío local a local:
 
```bash
telnet localhost 25
```
```
HELO servidor
MAIL FROM: alumno1@vuestrodominio
RCPT TO: alumno2@vuestrodominio
DATA
Asunto de prueba
.
QUIT
```
 
### Correo — Dovecot
 
```bash
ss -tlnp | grep -E "143|110"
```
 
### SSH
 
```bash
sudo service ssh status
ss -tlnp | grep :22
```
### Conectividad con el servidor (misma red interna)
 
```bash
ping -c 3 10.2.2.10
dig @10.2.2.10 servidor.vuestrodominio
telnet 10.2.2.10 25
telnet 10.2.2.10 143
ssh alumno@10.2.2.10 #usuario creado en el Dockerfile, usar "alumno" como password
sftp alumno@10.2.2.10
```
 
### Conectividad con la pasarela
 
```bash
ping -c 3 10.2.2.254            # debe funcionar (es su gateway directo)
```
 



 ## Kubernetes
```bash
sudo k3s kubectl create deployment prueba --image=nginx
sudo k3s kubectl scale deployment prueba --replicas=4
sudo k3s kubectl get pods -o wide        # mira la columna NODE: unos pods en cada nodo
sudo k3s kubectl delete deployment prueba
```

### Comprobar el estado actual
 
```bash
sudo systemctl status k3s                    # en el servidor
sudo systemctl status k3s-agent              # en el portátil
sudo k3s kubectl get nodes -o wide
```
 
```bash
sudo k3s kubectl get all --all-namespaces
sudo k3s kubectl get namespaces
sudo k3s kubectl get all -n alumno-jsanchez
sudo k3s kubectl get pvc -n alumno-jsanchez          # su volumen persistente
sudo k3s kubectl describe resourcequota cuota -n alumno-jsanchez
```

```bash
sudo k3s kubectl get pods --all-namespaces -o wide
sudo k3s kubectl top nodes
sudo k3s kubectl top pods --all-namespaces
sudo k3s ctr images ls | grep fso
```
 
---
 
### Crear pods / entornos nuevos
 
```bash
sed 's/ALUMNO/nombre/g' plantilla-alumno.yaml | sudo k3s kubectl apply -f -
sed 's/ALUMNO/nombre/g' entorno-alumno.yaml   | sudo k3s kubectl apply -f -
sudo k3s kubectl get pods -n alumno-nombre -o wide
```
```bash

sudo k3s kubectl create deployment reparto --image=nginx
sudo k3s kubectl scale deployment reparto --replicas=6
sudo k3s kubectl get pods -o wide
 ```

**Si sale ImagePullBackOff: importar la imagen en AMBAS VMs**
```bash
# En el equipo con Docker
docker save fso:latest -o fso.tar
scp fso.tar javier@<IP_SERVIDOR>:/home/javier/
scp fso.tar javier@<IP_AGENTE>:/home/javier/
# Dentro de cada VM
sudo k3s ctr images import fso.tar
sudo k3s kubectl rollout restart deployment/entorno -n alumno-nombre
```
 
**Prueba rápida con imagen pública (sin preparar nada)**
```bash
sudo k3s kubectl create deployment prueba --image=nginx
sudo k3s kubectl scale deployment prueba --replicas=4
sudo k3s kubectl get pods -o wide            # ver el reparto entre nodos
sudo k3s kubectl delete deployment prueba    # limpiar
```
 
---
 
### Apagar y encender entornos
 
```bash
sudo k3s kubectl scale deployment/entorno -n alumno-jsanchez --replicas=0    # apagar
sudo k3s kubectl scale deployment/entorno -n alumno-jsanchez --replicas=1    # encender
```
 
**Apagar TODOS los entornos de todos los alumnos**
```bash
for ns in $(sudo k3s kubectl get ns -o name | grep alumno- | cut -d/ -f2); do
  sudo k3s kubectl scale deployment --all -n $ns --replicas=0
done
```
 
**Encender TODOS los entornos**
```bash
for ns in $(sudo k3s kubectl get ns -o name | grep alumno- | cut -d/ -f2); do
  sudo k3s kubectl scale deployment --all -n $ns --replicas=1
done
```
 
**Comprobar que se apagaron / encendieron**
```bash
sudo k3s kubectl get pods --all-namespaces -o wide | grep alumno-
```
 
**Reiniciar un entorno (recrea el pod, mantiene el volumen)**
```bash
sudo k3s kubectl rollout restart deployment/entorno -n alumno-jsanchez
```
 
---
 
### Entrar y trabajar en un entorno
 
**Entrar al contenedor (vía administrador)**
```bash
POD=$(sudo k3s kubectl get pod -n alumno-jsanchez -l app=entorno -o jsonpath='{.items[0].metadata.name}')
sudo k3s kubectl exec -it -n alumno-jsanchez "$POD" -- bash
```
 
**Entrar por SSH (vía alumno) — vale la IP de cualquier nodo**
```bash
ssh alumno@<IP_SERVIDOR> -p 30022
```
 
**Ejecutar un comando suelto sin abrir sesión**
```bash
sudo k3s kubectl exec -n alumno-jsanchez "$POD" -- ls -l /home/alumno
```
 
**Ver los logs de un pod (si no arranca)**
```bash
sudo k3s kubectl logs -n alumno-jsanchez "$POD"
sudo k3s kubectl describe pod -n alumno-jsanchez "$POD"
```