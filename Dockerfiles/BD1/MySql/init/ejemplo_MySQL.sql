-- =============================================================================
-- Base de Datos 1 · Variante MySQL
-- Esquema de ejemplo para arrancar las prácticas.
-- Se ejecuta automáticamente la primera vez que se inicializa el contenedor
-- (colócalo en init/ y la imagen lo lanza desde /docker-entrypoint-initdb.d/).
-- Sustitúyelo / amplíalo con el enunciado real de cada práctica.
-- =============================================================================

CREATE TABLE IF NOT EXISTS departamento (
    id_dept   INT AUTO_INCREMENT PRIMARY KEY,
    nombre    VARCHAR(60) NOT NULL UNIQUE,
    ubicacion VARCHAR(60)
);

CREATE TABLE IF NOT EXISTS empleado (
    id_emp    INT AUTO_INCREMENT PRIMARY KEY,
    nombre    VARCHAR(60) NOT NULL,
    salario   DECIMAL(10,2) CHECK (salario >= 0),
    id_dept   INT,
    FOREIGN KEY (id_dept) REFERENCES departamento(id_dept)
);

INSERT IGNORE INTO departamento (nombre, ubicacion) VALUES
    ('Sistemas',   'Edificio A'),
    ('Desarrollo', 'Edificio B');

INSERT IGNORE INTO empleado (nombre, salario, id_dept) VALUES
    ('Ana',   28000, 1),
    ('Luis',  31000, 2);