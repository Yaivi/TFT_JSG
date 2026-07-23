-- =============================================================================
-- Base de Datos 1 · Variante Oracle
-- Esquema de ejemplo para arrancar las prácticas.
-- Se ejecuta automáticamente la primera vez que se inicializa el contenedor
-- (colócalo en init/ y la imagen lo lanza desde /container-entrypoint-initdb.d/).
-- Sustitúyelo / amplíalo con el enunciado real de cada práctica.
--
-- Notas de sintaxis Oracle:
--   - No existe SERIAL: se usa GENERATED ALWAYS AS IDENTITY.
--   - VARCHAR -> VARCHAR2 ; NUMERIC -> NUMBER.
--   - No hay ON CONFLICT: los INSERT se hacen por separado y se confirma (COMMIT).
-- =============================================================================
conn alumno/alumno@//localhost:1521/BD1

CREATE TABLE departamento (
    id_dept   NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre    VARCHAR2(60) NOT NULL UNIQUE,
    ubicacion VARCHAR2(60)
);

CREATE TABLE empleado (
    id_emp    NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre    VARCHAR2(60) NOT NULL,
    salario   NUMBER(10,2) CHECK (salario >= 0),
    id_dept   NUMBER REFERENCES departamento(id_dept)
);

INSERT INTO departamento (nombre, ubicacion) VALUES ('Sistemas',   'Edificio A');
INSERT INTO departamento (nombre, ubicacion) VALUES ('Desarrollo', 'Edificio B');

INSERT INTO empleado (nombre, salario, id_dept) VALUES ('Ana',  28000, 1);
INSERT INTO empleado (nombre, salario, id_dept) VALUES ('Luis', 31000, 2);

COMMIT;