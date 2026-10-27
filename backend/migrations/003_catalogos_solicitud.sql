-- Catálogos para eliminar la captura libre en el registro de solicitudes del Ejecutivo.
-- Aditiva: las columnas originales de SSNL se conservan y se siguen llenando con la descripción del catálogo.
CREATE TABLE IF NOT EXISTS Cat_Colonias (
 id INT AUTO_INCREMENT PRIMARY KEY,
 municipio_id INT NOT NULL,
 nombre VARCHAR(70) NOT NULL,
 codigo_postal CHAR(5) NOT NULL,
 tipo_asentamiento VARCHAR(40) NULL,
 is_active TINYINT(1) NOT NULL DEFAULT 1,
 created INT NULL,
 updated INT NULL,
 -- utf8mb4_unicode_ci compara sin distinguir mayúsculas ni acentos: «Centro» y «centro» son la misma colonia.
 UNIQUE KEY uq_colonia_ubicacion (municipio_id, codigo_postal, nombre),
 INDEX idx_colonia_cp (codigo_postal),
 CONSTRAINT fk_colonia_municipio FOREIGN KEY (municipio_id) REFERENCES INEGI_Cat_Municipios(id),
 CONSTRAINT chk_colonia_cp CHECK (codigo_postal REGEXP '^[0-9]{5}$')
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS Cat_ConQuienVive (
 id INT AUTO_INCREMENT PRIMARY KEY, descripcion VARCHAR(50) NOT NULL UNIQUE,
 is_active TINYINT(1) NOT NULL DEFAULT 1, created INT NULL, updated INT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
CREATE TABLE IF NOT EXISTS Cat_Ocupaciones (
 id INT AUTO_INCREMENT PRIMARY KEY, descripcion VARCHAR(150) NOT NULL UNIQUE,
 is_active TINYINT(1) NOT NULL DEFAULT 1, created INT NULL, updated INT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
CREATE TABLE IF NOT EXISTS Cat_FuentesIngreso (
 id INT AUTO_INCREMENT PRIMARY KEY, descripcion VARCHAR(150) NOT NULL UNIQUE,
 is_active TINYINT(1) NOT NULL DEFAULT 1, created INT NULL, updated INT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
CREATE TABLE IF NOT EXISTS Cat_AreasEstudio (
 id INT AUTO_INCREMENT PRIMARY KEY, descripcion VARCHAR(150) NOT NULL UNIQUE,
 is_active TINYINT(1) NOT NULL DEFAULT 1, created INT NULL, updated INT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT IGNORE INTO Cat_ConQuienVive (descripcion,created,updated) VALUES
 ('Solo(a)',UNIX_TIMESTAMP(),UNIX_TIMESTAMP()),('Pareja',UNIX_TIMESTAMP(),UNIX_TIMESTAMP()),
 ('Pareja e hijos(as)',UNIX_TIMESTAMP(),UNIX_TIMESTAMP()),('Hijos(as)',UNIX_TIMESTAMP(),UNIX_TIMESTAMP()),
 ('Padre y/o madre',UNIX_TIMESTAMP(),UNIX_TIMESTAMP()),('Otros familiares',UNIX_TIMESTAMP(),UNIX_TIMESTAMP()),
 ('Personas no familiares',UNIX_TIMESTAMP(),UNIX_TIMESTAMP()),('Institución o albergue',UNIX_TIMESTAMP(),UNIX_TIMESTAMP());
INSERT IGNORE INTO Cat_Ocupaciones (descripcion,created,updated) VALUES
 ('Empleado(a)',UNIX_TIMESTAMP(),UNIX_TIMESTAMP()),('Trabajador(a) por cuenta propia',UNIX_TIMESTAMP(),UNIX_TIMESTAMP()),
 ('Comerciante',UNIX_TIMESTAMP(),UNIX_TIMESTAMP()),('Profesionista',UNIX_TIMESTAMP(),UNIX_TIMESTAMP()),
 ('Obrero(a)',UNIX_TIMESTAMP(),UNIX_TIMESTAMP()),('Trabajador(a) del hogar',UNIX_TIMESTAMP(),UNIX_TIMESTAMP()),
 ('Labores del hogar',UNIX_TIMESTAMP(),UNIX_TIMESTAMP()),('Estudiante',UNIX_TIMESTAMP(),UNIX_TIMESTAMP()),
 ('Jubilado(a) o pensionado(a)',UNIX_TIMESTAMP(),UNIX_TIMESTAMP()),('Sin ocupación',UNIX_TIMESTAMP(),UNIX_TIMESTAMP());
INSERT IGNORE INTO Cat_FuentesIngreso (descripcion,created,updated) VALUES
 ('Sueldo o salario',UNIX_TIMESTAMP(),UNIX_TIMESTAMP()),('Negocio propio',UNIX_TIMESTAMP(),UNIX_TIMESTAMP()),
 ('Pensión o jubilación',UNIX_TIMESTAMP(),UNIX_TIMESTAMP()),('Programa social',UNIX_TIMESTAMP(),UNIX_TIMESTAMP()),
 ('Apoyo familiar',UNIX_TIMESTAMP(),UNIX_TIMESTAMP()),('Remesas',UNIX_TIMESTAMP(),UNIX_TIMESTAMP()),
 ('Sin ingresos',UNIX_TIMESTAMP(),UNIX_TIMESTAMP());
INSERT IGNORE INTO Cat_AreasEstudio (descripcion,created,updated) VALUES
 ('Educación básica',UNIX_TIMESTAMP(),UNIX_TIMESTAMP()),('Bachillerato o técnico',UNIX_TIMESTAMP(),UNIX_TIMESTAMP()),
 ('Ciencias de la salud',UNIX_TIMESTAMP(),UNIX_TIMESTAMP()),('Ingeniería y tecnología',UNIX_TIMESTAMP(),UNIX_TIMESTAMP()),
 ('Ciencias sociales y administrativas',UNIX_TIMESTAMP(),UNIX_TIMESTAMP()),('Educación y humanidades',UNIX_TIMESTAMP(),UNIX_TIMESTAMP()),
 ('Ciencias naturales y exactas',UNIX_TIMESTAMP(),UNIX_TIMESTAMP()),('Artes',UNIX_TIMESTAMP(),UNIX_TIMESTAMP()),
 ('Oficios',UNIX_TIMESTAMP(),UNIX_TIMESTAMP());
