# Laboratorio docente basado en Docker


## Arranque rápido
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
ssh alumno01@192.168.0.22 -p 2222

sudo docker ps -a --filter name=^alumno01-       
sudo docker compose -p alumno01-rc start         
sudo docker exec -it alumno01-rc-router-1 bash   
    



cd ASR
docker compose up -d --build
docker exec -it asr-cliente bash
docker exec -it asr-servidor bash
docker exec -it asr-pasarela bash
docker compose down  
```


# Validaciones 

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