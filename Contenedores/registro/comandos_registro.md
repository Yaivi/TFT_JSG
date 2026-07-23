# Pruebas del registro privado por roles
Comandos para probar que el registro privado funciona y que cada usuario tiene los
permisos que le tocan (profesor: lectura y escritura; alumno: solo lectura).

- **Registro:** `192.168.0.22:5000`
- **Usuarios:** `profesor` / `prueba1234` (acceso total) y `alumno` / `alumno1234` (solo lectura)

> RECORDATORIO: la imagen se nombra siempre como `192.168.0.22:5000/NOMBRE:ETIQUETA`.

 docker compose up -d

## 1. Sesión: entrar y salir
```powershell
# Iniciar sesión (te pedirá usuario y contraseña)
docker login 192.168.0.22:5000

# Cerrar sesión (borra las credenciales guardadas de ESE registro)
docker logout 192.168.0.22:5000
```

## 2. Preparar una imagen de prueba
```powershell
# Descargar una imagen mínima desde Docker Hub (algo que subir)
docker pull hello-world

# Etiquetarla apuntando a tu registro
docker tag hello-world 192.168.0.22:5000/prueba:1
```
- `pull hello-world`: trae una imagen pequeñita.
- `tag`: crea un nombre nuevo que apunta a registro. No copia datos, solo pone una "etiqueta".
> Para más imágenes de prueba: `docker pull alpine` y `docker tag alpine 192.168.0.22:5000/alpine:1`.



## 3. Prueba como PROFESOR (debe poder hacer TODO)
```powershell
docker logout 192.168.0.22:5000
docker login 192.168.0.22:5000        # profesor / prueba1234

# SUBIR (push) -> DEBE FUNCIONAR
docker push 192.168.0.22:5000/prueba:1 

# DESCARGAR (pull) -> DEBE FUNCIONAR
docker pull 192.168.0.22:5000/prueba:1
```
Resultado esperado: ambos comandos terminan correctamente.



## 4. Prueba como ALUMNO (solo LECTURA)
```powershell
docker logout 192.168.0.22:5000
docker login 192.168.0.22:5000        # alumno / alumno1234

# DESCARGAR (pull) -> DEBE FUNCIONAR
docker pull 192.168.0.22:5000/prueba:1

# SUBIR (push) -> DEBE SER DENEGADO  (este fallo es el resultado CORRECTO)
# probar con una imagen que no sea la del registro para verificar que no se sube
docker pull alpine
docker tag alpine 192.168.0.22:5000/test-alumno:1
docker push 192.168.0.22:5000/test-alumno:1
```
Resultado esperado:
- El `pull` funciona.
- El `push` **falla** con un error tipo `denied: requested access to the resource is denied o unauthorized`. 




## 5. Prueba SIN iniciar sesión (debe rechazar todo)
```powershell
docker logout 192.168.0.22:5000

# Cualquier acción sin login -> DEBE PEDIR AUTENTICACIÓN / SER DENEGADA
docker pull 192.168.0.22:5000/prueba:1
```
Resultado esperado: error de autenticación (`no basic auth credentials` / `unauthorized`). Confirma que el registro es realmente privado.




## 6. Consultar el contenido del registro (API REST)
El registro expone una API para listar lo que contiene. Útil para comprobar qué hay subido sin descargar nada. Necesita las credenciales (de ahí el `-u`):

```powershell
# Listar todos los repositorios (imágenes) del registro
curl.exe -k -u profesor:prueba1234 https://192.168.0.22:5000/v2/_catalog
docker exec registro sh -c 'ls "$(find / -path "*/registry/v2/repositories" -type d 2>/dev/null | head -1)"

# Listar las etiquetas (versiones) de una imagen concreta
curl.exe -k -u profesor:prueba1234 https://192.168.0.22:5000/v2/prueba/tags/list
```

- `_catalog` devuelve algo como `{"repositories":["prueba"]}`.
- `tags/list` devuelve `{"name":"prueba","tags":["1"]}`.
- `-k`: ignora la advertencia del certificado autofirmado (solo para esta comprobación manual).
- `-u usuario:contraseña`: envía las credenciales.





## 7. Limpieza local (opcional)
Borra las imágenes de **tu máquina** (no del registro), para repetir pruebas en limpio:

```powershell
docker image rm 192.168.0.22:5000/prueba:1
docker image rm hello-world

# Ver qué imágenes tienes en local
docker images
```
