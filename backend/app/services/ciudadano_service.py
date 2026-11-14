"""Módulo Ciudadano sobre SSNL.

La app del Ciudadano envía su propio modelo (perfil y solicitud en JSON). Aquí se traduce
a las tablas originales de SSNL para que el Ejecutivo vea y cuente esas solicitudes, y se
guarda en `ciudadano_solicitud.detalle` lo que SSNL no tiene dónde guardar.

Datos que SSNL exige y la app no captura se resuelven sin inventar información personal:
fecha de nacimiento, sexo y entidad de nacimiento salen de la CURP; el municipio de
nacimiento queda como «No especificado» (clave INEGI 999); con quién vive queda vacío para
que el personal lo complete.
"""
import json
import re
import uuid
from datetime import date, datetime
from zoneinfo import ZoneInfo

from fastapi import HTTPException
from pydantic import BaseModel, ConfigDict, Field, field_validator
from sqlalchemy import text

CURP = re.compile(r'^[A-Z][AEIOUX][A-Z]{2}\d{6}[HMX][A-Z]{2}[B-DF-HJ-NP-TV-Z]{3}[A-Z0-9]\d$')
CANAL = 'App SIEASAS Ciudadano'
ZONA = ZoneInfo('America/Mexico_City')
# createdBy/updatedBy de SSNL son enteros sin llave foránea; 0 identifica el alta desde la app.
AUTOR_APP = 0

ENTIDADES_CURP = {
    'AS': '01', 'BC': '02', 'BS': '03', 'CC': '04', 'CL': '05', 'CM': '06', 'CS': '07', 'CH': '08',
    'DF': '09', 'DG': '10', 'GT': '11', 'GR': '12', 'HG': '13', 'JC': '14', 'MC': '15', 'MN': '16',
    'MS': '17', 'NT': '18', 'NL': '19', 'OC': '20', 'PL': '21', 'QT': '22', 'QR': '23', 'SP': '24',
    'SL': '25', 'SR': '26', 'TC': '27', 'TS': '28', 'TL': '29', 'VZ': '30', 'YN': '31', 'ZS': '32',
}
SEXO = {'H': 'Masculino', 'M': 'Femenino', 'X': 'Prefiere no especificar'}

# Opciones de la app → descripción en los catálogos de SSNL.
TIPO_APOYO = {
    'Andadera, bastón o muletas': 'Equipos y aparatos',
    'Silla de ruedas': 'Equipos y aparatos',
    # Nombres anteriores de la app, para solicitudes y versiones ya instaladas.
    'Andadera o bastón': 'Equipos y aparatos',
    'Silla de ruedas o ayuda técnica': 'Equipos y aparatos',
    'Apoyo funerario': 'Apoyo Social',
    'Apoyo para cirugía': 'Cirugía',
    'Estudios o análisis clínicos': 'Estudios de Laboratorio',
    'Medicamento especializado': 'Medicamento',
    'Traslado médico': 'Ambulancias/Traslados',
    'Otro': 'Apoyo Social',
}
SEGURIDAD_SOCIAL = {
    'Cuidar tu Salud': 'Cuidar Tu Salud',
    'IMSS': 'Instituto Mexicano del Seguro Social',
    'IMSS-Bienestar': 'IMSS-Bienestar',
    'ISSSTE': 'Instituto de Seguridad y Servicios Sociales de los Trabajadores del Estado',
    'Otra': 'Otro',
    'Ninguna': 'Ninguno',
}
# SSNL guarda un solo grupo; se toma el primero de esta lista que el ciudadano haya marcado.
# Todos los que marcó quedan en las observaciones y en el detalle.
GRUPO_VULNERABLE = [
    ('Adulto mayor', 'Sí, Adulto Mayor'),
    ('Enfermedad crónica', 'Sí, Enfermedad crónica o terminal'),
    ('Persona con discapacidad', 'Sí, Discapacidad múltiple'),
    ('Niña, niño o adolescente', 'Sí, Niña, niño o adolescente'),
    ('Mujer embarazada', 'Sí, Mujer'),
    ('Situación de calle', 'Sí, Personas en situación de calle'),
]
SIN_GRUPO = 'No'

# Estatus de SSNL → estatus de la app y nota que ve el ciudadano.
ESTATUS = [
    ('Inicio', 'recibida', 'Tu solicitud fue registrada correctamente.'),
    ('En proceso', 'enRevision', 'Un enlace social está revisando tu solicitud.'),
    ('Resuelto con', 'atendidaConObservaciones', 'Tu solicitud fue atendida con observaciones.'),
    ('Resuelto', 'atendida', 'Tu solicitud fue atendida.'),
    ('No es competencia', 'noEsCompetencia',
     'La solicitud corresponde a otra dependencia; se te orientará sobre dónde presentarla.'),
    ('Cerrado', 'cancelada', 'La solicitud fue cerrada o cancelada.'),
]


class Entrada(BaseModel):
    # La app envía su modelo completo; se ignoran campos que el servidor no usa.
    model_config = ConfigDict(str_strip_whitespace=True, extra='ignore')


class MunicipioIn(Entrada):
    cvegeo: str = Field(pattern=r'^\d{5}$')
    nombre: str = Field(max_length=100)


class Perfil(Entrada):
    nombres: str = Field('', max_length=150)
    primerApellido: str = Field('', max_length=75)
    segundoApellido: str = Field('', max_length=75)
    curp: str = Field('', max_length=18)
    celular: str = Field('', max_length=20)
    correo: str = Field('', max_length=150)
    mediosContacto: list[str] = Field(default_factory=list, max_length=10)
    municipio: MunicipioIn | None = None
    codigoPostal: str = Field('', max_length=5)
    colonia: str = Field('', max_length=70)
    calle: str = Field('', max_length=150)
    numero: str = Field('', max_length=15)
    aceptaPrivacidad: bool = False
    avisoAceptadoEl: str | None = Field(None, max_length=40)
    avisoVersion: str = Field('', max_length=40)
    confirmaVeracidad: bool = False

    @field_validator('curp')
    @classmethod
    def curp_valida(cls, v):
        v = v.upper()
        if v and not CURP.match(v):
            raise ValueError('Revisa la CURP.')
        return v

    @property
    def apellidos(self):
        return ' '.join(p for p in (self.primerApellido, self.segundoApellido) if p)

    def completo(self):
        return all((self.nombres, self.primerApellido, self.curp, self.celular, self.municipio,
                    self.codigoPostal, self.colonia, self.calle, self.numero))


class BeneficiarioIn(Entrada):
    esTitular: bool
    nombres: str = Field('', max_length=150)
    primerApellido: str = Field('', max_length=75)
    segundoApellido: str = Field('', max_length=75)
    relacion: str = Field('', max_length=100)
    curp: str = Field('', max_length=18)

    _curp = field_validator('curp')(Perfil.curp_valida.__func__)


class UbicacionIn(Entrada):
    usaDomicilioRegistrado: bool
    municipio: MunicipioIn
    codigoPostal: str = Field(pattern=r'^\d{5}$')
    colonia: str = Field(min_length=1, max_length=70)
    calle: str = Field(min_length=1, max_length=150)
    numero: str = Field(min_length=1, max_length=15)
    referencias: str = Field('', max_length=500)


class SaludIn(Entrada):
    seguridadSocial: str = Field(max_length=60)
    tarjetaCuidarTuSalud: bool = False
    unidadMedica: str = Field('', max_length=150)
    gruposVulnerables: list[str] = Field(default_factory=list, max_length=20)


class AdjuntoIn(Entrada):
    nombre: str = Field(max_length=255)
    tamanoBytes: int = Field(ge=0)


class SolicitudIn(Entrada):
    asunto: str = Field(min_length=1, max_length=150)
    tipoApoyo: str = Field(max_length=100)
    descripcion: str = Field(min_length=1, max_length=4000)
    fechaRequerida: date
    riesgoInmediato: bool = False
    beneficiario: BeneficiarioIn
    ubicacion: UbicacionIn
    salud: SaludIn
    adjuntos: list[AdjuntoIn] = Field(default_factory=list, max_length=10)
    usaContactoCuenta: bool = True
    celularContacto: str = Field('', max_length=20)
    correoContacto: str = Field('', max_length=150)

    @field_validator('fechaRequerida', mode='before')
    @classmethod
    def solo_fecha(cls, v):
        return v[:10] if isinstance(v, str) else v


class NuevaSolicitud(BaseModel):
    model_config = ConfigDict(extra='forbid')
    idempotencia: uuid.UUID
    solicitud: SolicitudIn


# ---------------------------------------------------------------------------
# Traducciones puras (probadas sin base de datos)

def datos_curp(curp, hoy=None):
    """Fecha de nacimiento, sexo (H/M/X) y clave INEGI de la entidad de nacimiento ('' si nació fuera)."""
    hoy = hoy or date.today()
    yy, mm, dd = int(curp[4:6]), int(curp[6:8]), int(curp[8:10])
    siglo = 1900 if curp[16].isdigit() else 2000
    try:
        nacimiento = date(siglo + yy, mm, dd)
    except ValueError:
        raise HTTPException(422, 'La fecha de nacimiento de la CURP no es válida.')
    if nacimiento > hoy:
        raise HTTPException(422, 'La fecha de nacimiento de la CURP no es válida.')
    return nacimiento, curp[10], ENTIDADES_CURP.get(curp[11:13], '')


def edad(nacimiento, hoy=None):
    hoy = hoy or date.today()
    return hoy.year - nacimiento.year - ((hoy.month, hoy.day) < (nacimiento.month, nacimiento.day))


def _sin_acentos(texto):
    return texto.lower().translate(str.maketrans('áéíóúü', 'aeiouu'))


def parentesco(relacion, sexo_solicitante):
    """Parentesco del solicitante respecto del beneficiario.

    La app pregunta «¿Qué relación tienes con esta persona?» («Madre», «hijo»...), es decir,
    quién es el beneficiario para el ciudadano. SSNL guarda lo inverso. Devuelve la
    descripción del catálogo y, para «Otro», el texto original.
    """
    r = _sin_acentos(relacion.strip())
    mujer = sexo_solicitante == 'M'
    reglas = [
        (('padre', 'papa', 'madre', 'mama'), 'Hijo / Hija'),
        (('hijo', 'hija'), 'Madre' if mujer else 'Padre'),
        (('tio', 'tia'), 'Sobrino / Sobrina'),
        (('sobrin',), 'Tío / Tía'),
        (('prim',), 'Primo / Prima'),
        (('espos', 'pareja', 'marido', 'conyuge'), 'Esposo / Esposa'),
        (('amig',), 'Amigo / Amiga'),
        (('vecin',), 'Vecino / Vecina'),
        (('conocid',), 'Conocido / Conocida'),
    ]
    palabras = re.findall(r'[a-zñ]+', r)
    for claves, descripcion in reglas:
        if any(p.startswith(claves) for p in palabras):
            return descripcion, None
    return 'Otro', f'Beneficiario: {relacion.strip()}'[:100]


def grupo_vulnerable(grupos):
    for app, ssnl in GRUPO_VULNERABLE:
        if app in grupos:
            return ssnl
    return SIN_GRUPO


def estatus_app(descripcion):
    for prefijo, estatus, nota in ESTATUS:
        if (descripcion or '').startswith(prefijo):
            return estatus, nota
    return 'enRevision', ESTATUS[1][2]


def fecha_local(valor):
    """SSNL guarda UTC sin zona; la app espera la hora local de Nuevo León."""
    return valor.replace(tzinfo=ZoneInfo('UTC')).astimezone(ZONA).replace(tzinfo=None).isoformat()


def observaciones(s: SolicitudIn, nacio_fuera: bool):
    partes = [f'Registrada desde la app SIEASAS Ciudadano. Tipo de apoyo indicado: {s.tipoApoyo}.',
              f'Fecha en que se requiere: {s.fechaRequerida.strftime("%d/%m/%Y")}.']
    if s.riesgoInmediato:
        partes.append('El ciudadano indicó riesgo inmediato.')
    grupos = [g for g in s.salud.gruposVulnerables if g != 'Ninguno']
    partes.append('Grupos vulnerables indicados: ' + (', '.join(grupos) if grupos else 'ninguno') + '.')
    if s.salud.tarjetaCuidarTuSalud:
        partes.append('Tiene tarjeta Cuidar tu Salud.')
    if s.salud.unidadMedica:
        partes.append(f'Unidad médica: {s.salud.unidadMedica}.')
    if s.ubicacion.referencias:
        partes.append(f'Referencias del domicilio: {s.ubicacion.referencias}.')
    if s.adjuntos:
        partes.append(f'Documentos mencionados ({len(s.adjuntos)}): '
                      + ', '.join(a.nombre for a in s.adjuntos) + '. Los archivos no se reciben por la app.')
    if nacio_fuera:
        partes.append('Según la CURP, el beneficiario nació fuera de México.')
    partes.append('Pendiente de completar: municipio de nacimiento y con quién vive.')
    return ' '.join(partes)


# ---------------------------------------------------------------------------
# Acceso a SSNL

def catalogo(db, tabla, descripcion):
    valor = db.execute(text(f'SELECT id FROM `{tabla}` WHERE descripcion=:d AND is_active=1'), {'d': descripcion}).scalar()
    if valor is None:
        raise HTTPException(503, 'Falta configurar un catálogo de SSNL para el Ciudadano.')
    return valor


def municipio(db, cvegeo):
    row = db.execute(text('SELECT id,entidad_id FROM INEGI_Cat_Municipios WHERE cvegeo=:c'), {'c': cvegeo}).mappings().first()
    if not row:
        raise HTTPException(422, 'Selecciona un municipio válido.')
    return row


def entidad_por_clave(db, clave):
    return db.execute(text('SELECT id FROM INEGI_Cat_Entidades WHERE cve_ent=:c'), {'c': clave}).scalar()


def no_especificado(db, entidad_id):
    valor = db.execute(text("SELECT id FROM INEGI_Cat_Municipios WHERE entidad_id=:e AND cve_mun='999'"),
                       {'e': entidad_id}).scalar()
    if valor is None:
        raise HTTPException(503, 'Falta aplicar la migración del Ciudadano.')
    return valor


def colonia(db, municipio_id, nombre, cp):
    """Colonia del catálogo; si el ciudadano escribe una que no existe, se agrega."""
    params = {'m': municipio_id, 'n': nombre.strip()[:70], 'cp': cp}
    db.execute(text('''INSERT IGNORE INTO Cat_Colonias (municipio_id,nombre,codigo_postal,created,updated)
      VALUES (:m,:n,:cp,UNIX_TIMESTAMP(),UNIX_TIMESTAMP())'''), params)
    return db.execute(text('''SELECT id,nombre FROM Cat_Colonias
      WHERE municipio_id=:m AND codigo_postal=:cp AND nombre=:n'''), params).mappings().first()


def beneficiario(db, nombres, apellidos, curp, ubicacion: UbicacionIn, salud: SaludIn, es_titular):
    """Reutiliza la persona si su CURP ya está en SSNL; si no, la da de alta."""
    existente = db.execute(text('SELECT ben_id FROM Tbl_Beneficiarios WHERE ben_gen_curp=:c'), {'c': curp}).scalar()
    nacimiento, sexo, clave_nac = datos_curp(curp)
    if existente:
        return existente, clave_nac == ''
    mun = municipio(db, ubicacion.municipio.cvegeo)
    col = colonia(db, mun['id'], ubicacion.colonia, ubicacion.codigoPostal)
    entidad_nac = entidad_por_clave(db, clave_nac) if clave_nac else mun['entidad_id']
    params = {
        'nombres': nombres, 'apellidos': apellidos, 'curp': curp, 'nacimiento': nacimiento, 'edad': edad(nacimiento),
        'sexo': catalogo(db, 'Cat_Generos', SEXO[sexo]), 'entidad_nac': entidad_nac,
        'mun_nac': no_especificado(db, entidad_nac), 'calle': ubicacion.calle, 'numero': ubicacion.numero,
        'colonia': col['id'], 'cp': ubicacion.codigoPostal, 'entidad': mun['entidad_id'], 'municipio': mun['id'],
        'seguridad': catalogo(db, 'Cat_SeguridadSocial', SEGURIDAD_SOCIAL.get(salud.seguridadSocial, 'Otro')),
        'grupo': catalogo(db, 'Cat_GruposVulnerables', grupo_vulnerable(salud.gruposVulnerables)),
        'titular': es_titular, 'autor': AUTOR_APP,
    }
    ben_id = db.execute(text('''INSERT INTO Tbl_Beneficiarios
      (ben_gen_name,ben_gen_lastname,ben_gen_curp,ben_gen_isnocurp,ben_gen_birthdate,ben_gen_age,ben_gen_sex,
       ben_gen_entidad_nacimiento,ben_gen_municipio_nacimiento,ben_dom_calle,ben_dom_num,ben_dom_colonia,ben_dom_colonia_id,
       ben_dom_cp,ben_dom_entidad,ben_dom_municipio,ben_estsocioeco_conquienvive,ben_segsocial_segsocial_id,
       ben_misc_elmismotramita,ben_misc_grupovulnerable_id,is_active,createdBy,updatedBy)
      VALUES (:nombres,:apellidos,:curp,0,:nacimiento,:edad,:sexo,:entidad_nac,:mun_nac,:calle,:numero,:colonia,:colonia,
       :cp,:entidad,:municipio,'',:seguridad,:titular,:grupo,1,:autor,:autor)'''), params).lastrowid
    return ben_id, clave_nac == ''


def solicitante(db, perfil: Perfil, es_titular, relacion):
    nacimiento, sexo, _ = datos_curp(perfil.curp)
    descripcion, otro = ('El mismo / Ella misma', None) if es_titular else parentesco(relacion, sexo)
    mun = municipio(db, perfil.municipio.cvegeo)
    col = colonia(db, mun['id'], perfil.colonia, perfil.codigoPostal)
    return db.execute(text('''INSERT INTO Tbl_Solicitantes (sol_nombres,sol_apellidos,sol_parentescoid,sol_otroparentesco,
      sol_fecha_nacimiento,sol_calle,sol_numero,sol_colonia,sol_colonia_id,sol_codigopostal,sol_estadoid,sol_municipioid,
      sol_telefono,is_active,createdBy,updatedBy) VALUES (:nombres,:apellidos,:parentesco,:otro,:nacimiento,:calle,:numero,
      :colonia,:colonia_id,:cp,:entidad,:municipio,:telefono,1,:autor,:autor)'''), {
        'nombres': perfil.nombres[:100], 'apellidos': perfil.apellidos[:100],
        'parentesco': catalogo(db, 'Cat_Parentescos', descripcion), 'otro': otro, 'nacimiento': nacimiento,
        'calle': perfil.calle, 'numero': perfil.numero, 'colonia': col['nombre'], 'colonia_id': col['id'],
        'cp': perfil.codigoPostal, 'entidad': mun['entidad_id'], 'municipio': mun['id'],
        'telefono': re.sub(r'[^0-9+]', '', perfil.celular)[:20], 'autor': AUTOR_APP}).lastrowid


def perfil_de(db, cuenta_id):
    valor = db.execute(text('SELECT perfil FROM ciudadano_cuenta WHERE id=:id'), {'id': cuenta_id}).scalar()
    return Perfil.model_validate(json.loads(valor) if isinstance(valor, str) else (valor or {}))


SELECT_SOLICITUDES = '''SELECT cs.solicitud_id,cs.detalle,sa.created,sa.updated,st.descripcion AS estatus
  FROM ciudadano_solicitud cs JOIN Tbl_SolicitudesApoyo sa ON sa.solapoyo_id=cs.solicitud_id
  JOIN Cat_StatusAtencion st ON st.id=sa.solapoyo_statusid'''


def solicitud_app(row):
    """Solicitud con el formato de la app: detalle guardado + folio, fechas y estatus vivos de SSNL."""
    detalle = json.loads(row['detalle']) if isinstance(row['detalle'], str) else dict(row['detalle'])
    estatus, nota = estatus_app(row['estatus'])
    historial = [{'estatus': 'recibida', 'fecha': fecha_local(row['created']), 'nota': ESTATUS[0][2]}]
    if estatus != 'recibida':
        historial.append({'estatus': estatus, 'fecha': fecha_local(max(row['updated'], row['created'])), 'nota': nota})
    return {**detalle, 'folio': f'Solicitud #{row["solicitud_id"]}', 'fechaRegistro': fecha_local(row['created']),
            'estatus': estatus, 'historial': historial}


def listar(db, cuenta_id):
    rows = db.execute(text(SELECT_SOLICITUDES + ' WHERE cs.cuenta_id=:c ORDER BY sa.created DESC, cs.solicitud_id DESC'),
                      {'c': cuenta_id}).mappings().all()
    return [solicitud_app(r) for r in rows]


def una(db, solicitud_id):
    row = db.execute(text(SELECT_SOLICITUDES + ' WHERE cs.solicitud_id=:id'), {'id': solicitud_id}).mappings().first()
    return solicitud_app(row)


def crear(db, cuenta_id, data: NuevaSolicitud):
    clave = str(data.idempotencia)
    previa = db.execute(text('SELECT solicitud_id FROM ciudadano_solicitud WHERE cuenta_id=:c AND idempotencia=:k'),
                        {'c': cuenta_id, 'k': clave}).scalar()
    if previa:
        return una(db, previa)
    perfil = perfil_de(db, cuenta_id)
    if not perfil.completo():
        raise HTTPException(409, 'Completa tus datos antes de enviar una solicitud.')
    s = data.solicitud
    b = s.beneficiario
    if b.esTitular:
        nombres, apellidos, curp = perfil.nombres, perfil.apellidos, perfil.curp
    else:
        if not (b.nombres and b.primerApellido and b.curp and b.relacion):
            raise HTTPException(422, 'Completa los datos del beneficiario.')
        nombres = b.nombres
        apellidos = ' '.join(p for p in (b.primerApellido, b.segundoApellido) if p)
        curp = b.curp
    if s.tipoApoyo not in TIPO_APOYO:
        raise HTTPException(422, 'Selecciona un tipo de apoyo de la lista.')
    ben_id, nacio_fuera = beneficiario(db, nombres[:150], apellidos[:150], curp, s.ubicacion, s.salud, b.esTitular)
    sol_id = solicitante(db, perfil, b.esTitular, b.relacion)
    sid = db.execute(text('''INSERT INTO Tbl_SolicitudesApoyo (solapoyo_beneficiarioid,solapoyo_solicitanteid,
      solapoyo_enviadoporid,solapoyo_tipoapoyoid,solapoyo_descripcion,solapoyo_observaciones,solapoyo_statusid,
      solapoyo_canalrecepcionid,solapoyo_unidadtratanteid,createdBy,updatedBy)
      VALUES (:ben,:sol,:enviado,:tipo,:descripcion,:obs,:estatus,:canal,:unidad,:autor,:autor)'''), {
        'ben': ben_id, 'sol': sol_id, 'enviado': catalogo(db, 'Cat_EnviadoPor', 'Petición Ciudadana'),
        'tipo': catalogo(db, 'Cat_TipoApoyo', TIPO_APOYO[s.tipoApoyo]),
        'descripcion': f'{s.asunto}\n\n{s.descripcion}', 'obs': observaciones(s, nacio_fuera),
        'estatus': catalogo(db, 'Cat_StatusAtencion', 'Inicio'), 'canal': catalogo(db, 'Cat_CanalesRecepcion', CANAL),
        'unidad': catalogo(db, 'Cat_UnidadesTratantes', 'No especificado'), 'autor': AUTOR_APP}).lastrowid
    detalle = s.model_dump(mode='json')
    detalle['fechaRequerida'] = s.fechaRequerida.isoformat() + 'T00:00:00.000'
    if b.esTitular:
        detalle['beneficiario'].update(nombres=perfil.nombres, primerApellido=perfil.primerApellido,
                                       segundoApellido=perfil.segundoApellido, curp=perfil.curp, relacion='')
    db.execute(text('''INSERT INTO ciudadano_solicitud (solicitud_id,cuenta_id,idempotencia,detalle)
      VALUES (:sid,:c,:k,:d)'''), {'sid': sid, 'c': cuenta_id, 'k': clave, 'd': json.dumps(detalle, ensure_ascii=False)})
    return una(db, sid)


def actualizar_contacto(db, cuenta_id, perfil: Perfil):
    """El teléfono es el único dato de contacto que SSNL guarda: se refleja en sus solicitudes."""
    if not perfil.celular:
        return
    db.execute(text('''UPDATE Tbl_Solicitantes s JOIN Tbl_SolicitudesApoyo sa ON sa.solapoyo_solicitanteid=s.sol_id
      JOIN ciudadano_solicitud cs ON cs.solicitud_id=sa.solapoyo_id
      SET s.sol_telefono=:t, s.updatedBy=:autor WHERE cs.cuenta_id=:c'''),
               {'t': re.sub(r'[^0-9+]', '', perfil.celular)[:20], 'c': cuenta_id, 'autor': AUTOR_APP})


def borrar_cuenta(db, cuenta_id):
    """Elimina la cuenta, sus solicitudes y las personas que solo esas solicitudes usaban."""
    filas = db.execute(text('''SELECT sa.solapoyo_id,sa.solapoyo_beneficiarioid AS ben,sa.solapoyo_solicitanteid AS sol
      FROM ciudadano_solicitud cs JOIN Tbl_SolicitudesApoyo sa ON sa.solapoyo_id=cs.solicitud_id
      WHERE cs.cuenta_id=:c'''), {'c': cuenta_id}).mappings().all()
    ids = [f['solapoyo_id'] for f in filas]
    for sid in ids:
        db.execute(text('DELETE FROM ciudadano_solicitud WHERE solicitud_id=:id'), {'id': sid})
        db.execute(text('DELETE FROM Tbl_SolicitudesApoyo WHERE solapoyo_id=:id'), {'id': sid})
    for f in filas:
        db.execute(text('''DELETE FROM Tbl_Solicitantes WHERE sol_id=:id AND createdBy=:autor
          AND NOT EXISTS (SELECT 1 FROM Tbl_SolicitudesApoyo WHERE solapoyo_solicitanteid=:id)'''),
                   {'id': f['sol'], 'autor': AUTOR_APP})
        db.execute(text('''DELETE FROM Tbl_Beneficiarios WHERE ben_id=:id AND createdBy=:autor
          AND NOT EXISTS (SELECT 1 FROM Tbl_SolicitudesApoyo WHERE solapoyo_beneficiarioid=:id)'''),
                   {'id': f['ben'], 'autor': AUTOR_APP})
    db.execute(text('DELETE FROM ciudadano_cuenta WHERE id=:c'), {'c': cuenta_id})
    return len(ids)
