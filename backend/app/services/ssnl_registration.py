"""Registration validates the mandatory fields of the unmodified SSNL schema."""
import uuid
from datetime import date
from pydantic import BaseModel, Field, ConfigDict, model_validator, field_validator
from fastapi import HTTPException
from sqlalchemy import text
from sqlalchemy.exc import IntegrityError

class Input(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True, extra='forbid')

class Beneficiary(Input):
    nombres: str = Field(min_length=1,max_length=150)
    apellidos: str = Field(min_length=1,max_length=150)
    curp: str | None = Field(None,pattern=r'^[A-Z0-9]{18}$')
    fecha_nacimiento: date
    genero_id: int = Field(gt=0)
    municipio_nacimiento_id: int = Field(gt=0)
    municipio_id: int = Field(gt=0)
    calle: str = Field(min_length=1,max_length=150)
    numero: str = Field(min_length=1,max_length=15)
    colonia_id: int = Field(gt=0)
    tiempo_residencia: int = Field(ge=0,le=150)
    con_quien_vive_id: int = Field(gt=0)
    numero_hijos: int = Field(ge=0,le=100)
    hijo_seguridad_social: bool = False
    estudia: bool = False
    area_estudio_id: int | None = Field(None,gt=0)
    ocupacion_id: int | None = Field(None,gt=0)
    fuente_ingresos_id: int | None = Field(None,gt=0)
    seguridad_social_id: int = Field(gt=0)
    afiliacion: str | None = Field(None,max_length=150)
    grupo_vulnerable_id: int = Field(gt=0)
    tramita_personalmente: bool = False
    migrante: bool = False
    codigo2024: bool = False

    @field_validator('fecha_nacimiento')
    @classmethod
    def valid_birth(cls,v):
        if v > date.today() or v.year < date.today().year-150:
            raise ValueError('Revisa la fecha de nacimiento.')
        return v

    @model_validator(mode='after')
    def study_area(self):
        if self.estudia and self.area_estudio_id is None:
            raise ValueError('Selecciona el área de estudio.')
        if not self.estudia: self.area_estudio_id=None
        return self

class Applicant(Input):
    nombres: str = Field(min_length=1,max_length=100)
    apellidos: str = Field(min_length=1,max_length=100)
    parentesco_id: int = Field(gt=0)
    otro_parentesco: str | None = Field(None,max_length=100)
    fecha_nacimiento: date
    # Evita capturar dos veces la misma ubicación: el domicilio se copia del beneficiario.
    mismo_domicilio: bool = False
    calle: str | None = Field(None,min_length=1,max_length=150)
    numero: str | None = Field(None,min_length=1,max_length=20)
    colonia_id: int | None = Field(None,gt=0)
    municipio_id: int | None = Field(None,gt=0)
    telefono: str = Field(min_length=7,max_length=15,pattern=r'^[+0-9 ()-]+$')
    _birth=field_validator('fecha_nacimiento')(Beneficiary.valid_birth.__func__)

    @model_validator(mode='after')
    def own_address(self):
        fields=(self.calle,self.numero,self.colonia_id,self.municipio_id)
        if self.mismo_domicilio and any(v is not None for v in fields):
            raise ValueError('Con el mismo domicilio del beneficiario no se captura otra ubicación.')
        if not self.mismo_domicilio and any(v is None for v in fields):
            raise ValueError('Completa el domicilio del solicitante o indica que es el mismo del beneficiario.')
        return self

class NewRequest(Input):
    beneficiario_id: int | None = Field(None,gt=0)
    beneficiario: Beneficiary | None = None
    solicitante_id: int | None = Field(None,gt=0)
    solicitante: Applicant | None = None
    tipo_apoyo_id: int = Field(gt=0)
    enviado_por_id: int = Field(gt=0)
    canal_id: int = Field(gt=0)
    unidad_tratante_id: int = Field(gt=0)
    dependencia_id: int | None = Field(None,gt=0)
    partido_id: int | None = Field(None,gt=0)
    municipio_remitente_id: int | None = Field(None,gt=0)
    detalles_envio: str | None = Field(None,max_length=150)
    descripcion: str = Field(min_length=1,max_length=5000)
    observaciones: str | None = Field(None,max_length=5000)
    idempotencia: uuid.UUID

    @model_validator(mode='after')
    def one_person_source(self):
        if (self.beneficiario_id is None)==(self.beneficiario is None):
            raise ValueError('Selecciona un beneficiario existente o captura uno nuevo.')
        if (self.solicitante_id is None)==(self.solicitante is None):
            raise ValueError('Selecciona un solicitante existente o captura uno nuevo.')
        return self


def require_catalog(db,table,value):
    if value is not None and not db.execute(text(f'SELECT id FROM `{table}` WHERE id=:id AND is_active=1'),{'id':value}).scalar():
        raise HTTPException(422,'Una opción seleccionada ya no está disponible. Actualiza los catálogos.')


def catalog_value(db,table,value):
    """Descripción de un elemento activo; SSNL guarda el texto en sus columnas originales."""
    if value is None: return None
    label=db.execute(text(f'SELECT descripcion FROM `{table}` WHERE id=:id AND is_active=1'),{'id':value}).scalar()
    if label is None:
        raise HTTPException(422,'Una opción seleccionada ya no está disponible. Actualiza los catálogos.')
    return label


def colony(db,cid,mid):
    row=db.execute(text('SELECT id,nombre,codigo_postal FROM Cat_Colonias WHERE id=:id AND municipio_id=:m AND is_active=1'),
      {'id':cid,'m':mid}).mappings().first()
    if not row:
        raise HTTPException(422,'La colonia no corresponde al municipio seleccionado.')
    return row


def beneficiary_address(db,bid):
    # ben_dom_colonia es numérica en SSNL: el nombre sale del catálogo (o de la clave, en expedientes antiguos).
    return db.execute(text('''SELECT b.ben_dom_calle AS calle,b.ben_dom_num AS numero,
      COALESCE(c.nombre,CAST(b.ben_dom_colonia AS CHAR)) AS colonia,
      b.ben_dom_colonia_id AS colonia_id,b.ben_dom_cp AS codigo_postal,b.ben_dom_municipio AS municipio_id
      FROM Tbl_Beneficiarios b LEFT JOIN Cat_Colonias c ON c.id=b.ben_dom_colonia_id WHERE b.ben_id=:id'''),{'id':bid}).mappings().first()


def municipality(db,mid,eid=None):
    row=db.execute(text('SELECT id,entidad_id FROM INEGI_Cat_Municipios WHERE id=:id'),{'id':mid}).mappings().first()
    if not row or (eid is not None and row['entidad_id']!=eid):
        raise HTTPException(422,'Selecciona un municipio válido del estado asignado.')
    return row


def existing_request(db,user,key):
    return db.execute(text('''SELECT sa.solapoyo_id AS solicitud_id,CONCAT('Solicitud #',sa.solapoyo_id) AS folio
      FROM ejecutivo_registro er JOIN Tbl_SolicitudesApoyo sa ON sa.solapoyo_id=er.solicitud_id
      JOIN Tbl_Beneficiarios b ON b.ben_id=sa.solapoyo_beneficiarioid
      WHERE er.usuario_id=:uid AND er.idempotencia=:key AND b.ben_dom_entidad=:eid'''),
      {'uid':user['usuario_id'],'key':str(key),'eid':user['entidad_id']}).mappings().first()


def create_request(data,user,db):
    previous=existing_request(db,user,data.idempotencia)
    if previous: return dict(previous)
    uid=user['usuario_id']; eid=user['entidad_id']
    for table,value in [('Cat_TipoApoyo',data.tipo_apoyo_id),('Cat_EnviadoPor',data.enviado_por_id),
      ('Cat_CanalesRecepcion',data.canal_id),('Cat_UnidadesTratantes',data.unidad_tratante_id),
      ('Cat_Dependencias',data.dependencia_id),('Cat_PartidosPoliticos',data.partido_id)]:
        require_catalog(db,table,value)
    if data.municipio_remitente_id: municipality(db,data.municipio_remitente_id,eid)
    status=db.execute(text("SELECT id FROM Cat_StatusAtencion WHERE descripcion='Inicio' AND is_active=1")).scalar()
    if not status: raise HTTPException(503,'No está configurado el estatus inicial de SSNL.')
    bid=data.beneficiario_id; aid=data.solicitante_id
    if bid and not db.execute(text('''SELECT b.ben_id FROM Tbl_Beneficiarios b JOIN INEGI_Cat_Municipios m
      ON m.id=b.ben_dom_municipio AND m.entidad_id=b.ben_dom_entidad
      WHERE b.ben_id=:id AND b.ben_dom_entidad=:eid AND b.is_active=1'''),{'id':bid,'eid':eid}).scalar():
        raise HTTPException(422,'Beneficiario no disponible en tu estado.')
    if aid and not db.execute(text('''SELECT s.sol_id FROM Tbl_Solicitantes s JOIN INEGI_Cat_Municipios m
      ON m.id=s.sol_municipioid AND m.entidad_id=s.sol_estadoid
      WHERE s.sol_id=:id AND s.sol_estadoid=:eid AND s.is_active=1'''),{'id':aid,'eid':eid}).scalar():
        raise HTTPException(422,'Solicitante no disponible en tu estado.')
    social={}
    if data.beneficiario:
        b=data.beneficiario
        municipality(db,b.municipio_id,eid)
        birth=municipality(db,b.municipio_nacimiento_id)
        for table,value in [('Cat_Generos',b.genero_id),('Cat_SeguridadSocial',b.seguridad_social_id),('Cat_GruposVulnerables',b.grupo_vulnerable_id)]:
            require_catalog(db,table,value)
        home=colony(db,b.colonia_id,b.municipio_id)
        social={'con_quien_vive':catalog_value(db,'Cat_ConQuienVive',b.con_quien_vive_id),
          'area_estudio':catalog_value(db,'Cat_AreasEstudio',b.area_estudio_id),
          'profesion':catalog_value(db,'Cat_Ocupaciones',b.ocupacion_id),
          'fuente_ingresos':catalog_value(db,'Cat_FuentesIngreso',b.fuente_ingresos_id),
          # ben_dom_colonia es INT en SSNL: guarda la clave del catálogo, igual que ben_dom_colonia_id.
          'colonia':b.colonia_id,'codigo_postal':home['codigo_postal']}
    applicant_home={}
    if data.solicitante:
        a=data.solicitante
        if a.mismo_domicilio:
            if data.beneficiario:
                applicant_home={'calle':b.calle,'numero':b.numero,'colonia':home['nombre'],'colonia_id':b.colonia_id,
                  'codigo_postal':home['codigo_postal'],'municipio_id':b.municipio_id}
            else:
                applicant_home=dict(beneficiary_address(db,bid))
        else:
            municipality(db,a.municipio_id,eid)
            place=colony(db,a.colonia_id,a.municipio_id)
            applicant_home={'calle':a.calle,'numero':a.numero,'colonia':place['nombre'],'colonia_id':a.colonia_id,
              'codigo_postal':place['codigo_postal'],'municipio_id':a.municipio_id}
        require_catalog(db,'Cat_Parentescos',a.parentesco_id)
        relation=db.execute(text('SELECT descripcion FROM Cat_Parentescos WHERE id=:id'),{'id':a.parentesco_id}).scalar()
        if relation=='Otro' and not a.otro_parentesco:
            raise HTTPException(422,'Especifica el parentesco del solicitante.')
    try:
        if data.beneficiario:
            b=data.beneficiario
            today=date.today(); age=today.year-b.fecha_nacimiento.year-((today.month,today.day)<(b.fecha_nacimiento.month,b.fecha_nacimiento.day))
            bid=db.execute(text('''INSERT INTO Tbl_Beneficiarios
              (ben_gen_name,ben_gen_lastname,ben_gen_curp,ben_gen_isnocurp,ben_gen_birthdate,ben_gen_age,ben_gen_sex,
               ben_gen_entidad_nacimiento,ben_gen_municipio_nacimiento,ben_dom_calle,ben_dom_num,ben_dom_colonia,ben_dom_colonia_id,
               ben_dom_cp,ben_dom_entidad,ben_dom_municipio,ben_dom_tiemporesidencia,
               ben_estsocioeco_conquienvive,ben_estsocioeco_numhijos,ben_estsocioeco_hijoconsegsocial,
               ben_estsocioeco_estudiaactualmente,ben_estsocioeco_estudiaactualmente_areaestudio,ben_estsocioeco_profesion,
               ben_estsocioeco_fuenteingresos,ben_segsocial_segsocial_id,ben_segsocial_numafiliacion,
               ben_misc_elmismotramita,ben_misc_grupovulnerable_id,ben_misc_ismigrante,ben_misc_iscodigo2024,is_active,createdBy,updatedBy)
              VALUES (:nombres,:apellidos,:curp,:no_curp,:fecha_nacimiento,:edad,:genero_id,
               :birth_eid,:municipio_nacimiento_id,:calle,:numero,:colonia,:colonia_id,:codigo_postal,:eid,:municipio_id,:tiempo_residencia,
               :con_quien_vive,:numero_hijos,:hijo_seguridad_social,:estudia,:area_estudio,:profesion,:fuente_ingresos,
               :seguridad_social_id,:afiliacion,:tramita_personalmente,:grupo_vulnerable_id,:migrante,:codigo2024,1,:uid,:uid)'''),
              {**b.model_dump(),**social,'uid':uid,'eid':eid,'edad':age,'birth_eid':birth['entidad_id'],'no_curp':b.curp is None}).lastrowid
        if data.solicitante:
            a=data.solicitante
            aid=db.execute(text('''INSERT INTO Tbl_Solicitantes (sol_nombres,sol_apellidos,sol_parentescoid,sol_otroparentesco,
              sol_fecha_nacimiento,sol_calle,sol_numero,sol_colonia,sol_colonia_id,sol_codigopostal,sol_estadoid,sol_municipioid,sol_telefono,
              is_active,createdBy,updatedBy) VALUES (:nombres,:apellidos,:parentesco_id,:otro_parentesco,:fecha_nacimiento,
              :calle,:numero,:colonia,:colonia_id,:codigo_postal,:eid,:municipio_id,:telefono,1,:uid,:uid)'''),
              {**a.model_dump(),**applicant_home,'eid':eid,'uid':uid}).lastrowid
        sid=db.execute(text('''INSERT INTO Tbl_SolicitudesApoyo (solapoyo_beneficiarioid,solapoyo_solicitanteid,
          solapoyo_enviadoporid,solapoyo_enviadopor_dependenciaid,solapoyo_enviadopor_partidopoliticoid,
          solapoyo_enviadopor_municipioid,solapoyo_enviadopor_detalles,solapoyo_tipoapoyoid,
          solapoyo_descripcion,solapoyo_observaciones,solapoyo_statusid,solapoyo_canalrecepcionid,solapoyo_unidadtratanteid,
          createdBy,updatedBy) VALUES (:bid,:aid,:enviado_por_id,:dependencia_id,:partido_id,:municipio_remitente_id,
          :detalles_envio,:tipo_apoyo_id,:descripcion,:observaciones,:status,:canal_id,:unidad_tratante_id,:uid,:uid)'''),
          {**data.model_dump(),'bid':bid,'aid':aid,'status':status,'uid':uid}).lastrowid
        db.execute(text('INSERT INTO ejecutivo_registro (solicitud_id,usuario_id,idempotencia) VALUES (:sid,:uid,:key)'),
          {'sid':sid,'uid':uid,'key':str(data.idempotencia)})
        db.commit()
        return {'solicitud_id':sid,'folio':f'Solicitud #{sid}'}
    except IntegrityError:
        db.rollback()
        previous=existing_request(db,user,data.idempotencia)
        if previous: return dict(previous)
        raise HTTPException(409,'No se pudo guardar. Si la CURP ya existe, selecciona el beneficiario registrado; revisa también los catálogos.')
