# Ensayo de instalación sobre la base SSNL

Comprueba, en un MySQL **de prueba**, que el Ejecutivo se instala sobre la base SSNL de referencia sin
cambiar nada de SSNL y que funciona sobre ella.

**Base de referencia:** la que generan las migraciones de Yii del repositorio
[`TheRadikalStyle/ssnl-gestoria-apoyos`](https://github.com/TheRadikalStyle/ssnl-gestoria-apoyos) en el
commit `710a73a` (13/11/2026), más las migraciones RBAC de Yii.

## Qué hace

1. Crea una base vacía en el MySQL de prueba (la borra si ya existe).
2. Aplica las migraciones de SSNL y las de RBAC de Yii (`migrar_ssnl.php`).
3. Aplica `backend/manage.py migrate` **dos veces**, para comprobar que se puede repetir.
4. Compara la estructura antes y después (`esquema.py` y `diferencia_instalacion.py`). Solo se aceptan:
   - las tablas `Cat_Colonias`, `Cat_ConQuienVive`, `Cat_Ocupaciones`, `Cat_FuentesIngreso` y `Cat_AreasEstudio`;
   - las columnas `Tbl_Beneficiarios.ben_dom_colonia_id` y `Tbl_Solicitantes.sol_colonia_id`, con su FK.

   Cualquier otro cambio (una tabla o columna de SSNL modificada, borrada o agregada) hace fallar el ensayo.
5. Corre las pruebas del backend con MySQL real (`RUN_DB_TESTS=1`).

## Cómo correrlo

Requisitos: un MySQL 8 de prueba, el cliente `mysql` en el `PATH`, PHP 8.2 con `pdo_mysql`, el
repositorio SSNL en el commit de referencia con su carpeta `vendor` (`composer install`), y el entorno de
Python del backend.

```powershell
git clone https://github.com/TheRadikalStyle/ssnl-gestoria-apoyos.git C:\ssnl
git -C C:\ssnl checkout 710a73a
# (instalar sus dependencias con Composer en C:\ssnl)

.\pruebas\instalacion\ensayo_instalacion.ps1 -Bd ensayo_sgsc -SsnlRepo C:\ssnl `
    -Php C:\php\php.exe -Python .\backend\.venv\Scripts\python.exe
```

- `-Collation utf8mb4_0900_ai_ci` repite el ensayo con otra collation; las tablas nuevas toman la de la base.
- Si no se define `AUTH_ENCRYPTION_KEY`, el ensayo genera una clave temporal para las pruebas del segundo factor.

**Nunca** se debe apuntar a una base con datos reales: el ensayo borra y vuelve a crear la base indicada.

## Último resultado (20/11/2026)

MySQL 8.0.31 local, con `utf8mb4_unicode_ci` y con `utf8mb4_0900_ai_ci`:

- la instalación agregó solo los 5 catálogos y las 2 columnas de colonia, sin cambios en SSNL;
- `migrate` se repitió sin efectos adicionales;
- pruebas del backend con MySQL real: 83 pasan (10 omitidas: inspección del PDF, que requiere `pypdf`).
