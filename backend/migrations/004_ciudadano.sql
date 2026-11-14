-- Módulo Ciudadano. Aditiva: las tablas originales de SSNL no cambian de estructura.
-- Las solicitudes del ciudadano se guardan en Tbl_SolicitudesApoyo (y sus personas en
-- Tbl_Beneficiarios / Tbl_Solicitantes) para que el Ejecutivo las vea; estas tablas solo
-- guardan la cuenta, la sesión y los datos que SSNL no tiene dónde guardar.
CREATE TABLE IF NOT EXISTS ciudadano_cuenta (
 id INT AUTO_INCREMENT PRIMARY KEY,
 correo VARCHAR(180) NOT NULL UNIQUE,
 password_hash VARCHAR(255) NOT NULL,
 -- Perfil tal como lo captura la app (nombre, CURP, contacto, domicilio, consentimientos).
 perfil JSON NULL,
 creado DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
 actualizado DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
CREATE TABLE IF NOT EXISTS ciudadano_sesion (
 token_hash CHAR(64) PRIMARY KEY,
 cuenta_id INT NOT NULL,
 expira DATETIME NOT NULL,
 creado DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
 FOREIGN KEY (cuenta_id) REFERENCES ciudadano_cuenta(id) ON DELETE CASCADE,
 INDEX idx_ciudadano_sesion_expira (expira)
) ENGINE=InnoDB;
CREATE TABLE IF NOT EXISTS ciudadano_solicitud (
 solicitud_id INT PRIMARY KEY,
 cuenta_id INT NOT NULL,
 idempotencia CHAR(36) NOT NULL,
 -- Lo que el ciudadano capturó y SSNL no guarda: asunto, tipo de apoyo en sus palabras,
 -- fecha requerida, grupos vulnerables, documentos (solo nombre y tamaño), contacto.
 detalle JSON NOT NULL,
 creado DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
 UNIQUE KEY uq_ciudadano_reintento (cuenta_id, idempotencia),
 FOREIGN KEY (solicitud_id) REFERENCES Tbl_SolicitudesApoyo(solapoyo_id) ON DELETE CASCADE,
 FOREIGN KEY (cuenta_id) REFERENCES ciudadano_cuenta(id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- Canal de recepción de las solicitudes que llegan por la app.
INSERT INTO Cat_CanalesRecepcion (descripcion,is_active,created,updated)
 SELECT 'App SIEASAS Ciudadano',1,UNIX_TIMESTAMP(),UNIX_TIMESTAMP() FROM DUAL
 WHERE NOT EXISTS (SELECT 1 FROM Cat_CanalesRecepcion WHERE descripcion='App SIEASAS Ciudadano');

-- La CURP indica la entidad de nacimiento, no el municipio. SSNL exige el municipio de
-- nacimiento; se usa la clave 999 «No especificado» de INEGI en lugar de inventar uno.
INSERT INTO INEGI_Cat_Municipios (entidad_id,cvegeo,cve_ent,nom_ent,nom_abr,cve_mun,nom_mun,cve_cab,
 pob_total,pob_masculina,pob_femenina,total_viviendas_habitadas)
 SELECT e.id,CONCAT(e.cve_ent,'999'),e.cve_ent,e.nom_ent,e.nom_abr,'999','No especificado','0000','','','',''
 FROM INEGI_Cat_Entidades e
 WHERE NOT EXISTS (SELECT 1 FROM INEGI_Cat_Municipios m WHERE m.entidad_id=e.id AND m.cve_mun='999');
