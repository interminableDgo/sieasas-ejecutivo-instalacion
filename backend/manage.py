"""Local administration: no public account-provisioning endpoint."""
import argparse
import getpass
from pathlib import Path

from sqlalchemy import text

from app.database import engine
from app.security import hasher


COLONY_COLUMNS={'Tbl_Beneficiarios':'ben_dom_colonia_id','Tbl_Solicitantes':'sol_colonia_id'}


def run_sql(db,name):
    sql=(Path(__file__).parent/'migrations'/name).read_text(encoding='utf-8')
    sql='\n'.join(line for line in sql.splitlines() if not line.lstrip().startswith('--'))
    for statement in sql.split(';'):
        if statement.strip():
            db.execute(text(statement))


def migrate():
    with engine.begin() as db:
        run_sql(db,'002_ssnl_ejecutivo.sql')
        run_sql(db,'003_catalogos_solicitud.sql')
        run_sql(db,'004_ciudadano.sql')
        # MySQL 8 no admite ADD COLUMN IF NOT EXISTS; se comprueba antes para que la migración sea repetible.
        for table,column in COLONY_COLUMNS.items():
            exists=db.execute(text('''SELECT COUNT(*) FROM information_schema.COLUMNS
              WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME=:t AND COLUMN_NAME=:c'''),{'t':table,'c':column}).scalar()
            if not exists:
                db.execute(text(f'ALTER TABLE `{table}` ADD COLUMN `{column}` INT NULL, '
                                f'ADD CONSTRAINT `fk_{column}` FOREIGN KEY (`{column}`) REFERENCES Cat_Colonias(id)'))
    print('Migración aditiva aplicada.')


def load_colonies(args):
    """Carga el catálogo de SEPOMEX (CPdescarga.txt, separado por «|») sin duplicar colonias."""
    lines=Path(args.archivo).read_text(encoding=args.codificacion).splitlines()
    header=next(i for i,line in enumerate(lines) if line.startswith('d_codigo|'))
    columns=lines[header].split('|')
    added=skipped=0
    with engine.begin() as db:
        municipalities={row.cvegeo:row.id for row in db.execute(text('SELECT id,cvegeo FROM INEGI_Cat_Municipios'))}
        for line in lines[header+1:]:
            row=dict(zip(columns,line.split('|')))
            if args.estado and row.get('c_estado')!=args.estado: continue
            mid=municipalities.get(row.get('c_estado','')+row.get('c_mnpio',''))
            if not mid or not row.get('d_asenta'): skipped+=1; continue
            added+=db.execute(text('''INSERT IGNORE INTO Cat_Colonias (municipio_id,nombre,codigo_postal,tipo_asentamiento,created,updated)
              VALUES (:m,:n,:cp,:t,UNIX_TIMESTAMP(),UNIX_TIMESTAMP())'''),
              {'m':mid,'n':row['d_asenta'].strip()[:70],'cp':row['d_codigo'],'t':row.get('d_tipo_asenta')}).rowcount
    print(f'Colonias nuevas: {added}. Omitidas por municipio desconocido: {skipped}. Las repetidas no se duplican.')


def seed():
    raise SystemExit('SSNL utiliza sus catálogos originales. No se cargan los catálogos del wireframe.')


def provision(args):
    with engine.begin() as db:
        entity=db.execute(text('SELECT id FROM INEGI_Cat_Entidades WHERE cve_ent=:code'),{'code':args.entidad}).scalar_one()
        uid=db.execute(text('SELECT us_id FROM Tbl_Users WHERE us_email=:email'),{'email':args.correo}).scalar()
        if uid:
            raise SystemExit('La cuenta ya existe. No se modificó.')
        pending=db.execute(text('SELECT password_hash FROM ejecutivo_acceso_solicitud WHERE correo=:email'),{'email':args.correo}).scalar()
        if not pending:
            password=getpass.getpass('Contraseña inicial (15–128 caracteres): ')
            if not 15 <= len(password) <= 128:
                raise SystemExit('Longitud inválida.')
            pending=hasher.hash(password)
        uid=db.execute(text("""INSERT INTO Tbl_Users
          (us_name,us_lastname,us_email,us_account,us_pwd,us_phone,us_rol,is_active,createdBy,updatedBy)
          VALUES (:n,:a,:e,:e,:p,:phone,'Ejecutivo',1,0,0)"""),
          {'n':args.nombres,'a':args.apellidos,'e':args.correo,'p':pending,'phone':args.telefono}).lastrowid
        db.execute(text('UPDATE Tbl_Users SET createdBy=:u,updatedBy=:u WHERE us_id=:u'),{'u':uid})
        db.execute(text("INSERT INTO auth_assignment (item_name,user_id,created_at) VALUES ('Ejecutivo',:u,UNIX_TIMESTAMP())"),{'u':str(uid)})
        db.execute(text('INSERT INTO ejecutivo_acceso (usuario_id,entidad_id) VALUES (:u,:e)'),{'u':uid,'e':entity})
        db.execute(text('DELETE FROM ejecutivo_acceso_solicitud WHERE correo=:email'),{'email':args.correo})
    print('Cuenta ejecutiva autorizada en SSNL.')


def setup_2fa(args):
    import pyotp
    from app.security import cipher
    with engine.begin() as db:
        uid=db.execute(text('SELECT us_id FROM Tbl_Users WHERE us_email=:email AND is_active=1'),{'email':args.correo}).scalar_one()
        current=db.execute(text('SELECT totp_secret FROM ejecutivo_acceso WHERE usuario_id=:uid'),{'uid':uid}).scalar_one()
        if current:
            raise SystemExit('La cuenta ya tiene verificación en dos pasos. No se modificó.')
        totp=pyotp.TOTP(pyotp.random_base32())
        print('Agrega esta clave en tu aplicación de autenticación:',totp.secret)
        code=getpass.getpass('Escribe el código de 6 dígitos para confirmar la vinculación: ')
        if not totp.verify(code,valid_window=1):
            raise SystemExit('Código incorrecto. No se activó la verificación.')
        db.execute(text('UPDATE ejecutivo_acceso SET totp_secret=:s WHERE usuario_id=:uid'),{'s':cipher().encrypt(totp.secret.encode()).decode(),'uid':uid})
    print('Verificación en dos pasos activada.')


DEMO_CORREO='demo@sieasas.mx'
DEMO_PERFIL={'nombres':'María','primerApellido':'Rodríguez','segundoApellido':'Gómez','curp':'ROGM900101MNLDRR05',
  'celular':'81 1234 5678','correo':DEMO_CORREO,'mediosContacto':['WhatsApp'],
  'municipio':{'cvegeo':'19039','nombre':'Monterrey'},'codigoPostal':'64000','colonia':'Centro',
  'calle':'Calle Juárez','numero':'123','aceptaPrivacidad':True,'avisoVersion':'demostrativa 1','confirmaVeracidad':True}
# (asunto, tipo de apoyo de la app, descripción, días atrás, estatus SSNL, días hasta el cambio de estatus)
DEMO_SOLICITUDES=[
  ('Solicitud de silla de ruedas','Silla de ruedas o ayuda técnica','Necesito una silla de ruedas para trasladarme dentro y fuera de casa.',12,'En proceso(Pendiente)',3),
  ('Apoyo con medicamento especializado','Medicamento especializado','Requiero un medicamento para tratamiento de enfermedad crónica que no surte mi clínica.',40,'Resuelto',9),
  ('Estudios de laboratorio','Estudios o análisis clínicos','Me solicitaron estudios de laboratorio para dar seguimiento a mi tratamiento.',65,'Resuelto con observación',10),
  ('Apoyo funerario','Apoyo funerario','Solicito apoyo para los gastos funerarios de un familiar.',80,'No es competencia',4),
  ('Traslado médico','Traslado médico','Necesito traslado a una cita de especialidad en otro municipio.',95,'Cerrado / Cancelado',2),
]


def demo_ciudadano(args):
    """Crea o restablece la cuenta demo del Ciudadano: perfil de María y 5 solicitudes en distintos estatus."""
    import json, uuid
    from datetime import date, timedelta
    from sqlalchemy.orm import Session
    from app.services import ciudadano_service as svc
    with Session(engine) as db:
        previa=db.execute(text('SELECT id FROM ciudadano_cuenta WHERE correo=:c'),{'c':DEMO_CORREO}).scalar()
        if previa: svc.borrar_cuenta(db,previa)
        cid=db.execute(text('INSERT INTO ciudadano_cuenta (correo,password_hash,perfil) VALUES (:c,:p,:perfil)'),
          {'c':DEMO_CORREO,'p':hasher.hash(args.contrasena),'perfil':json.dumps(DEMO_PERFIL,ensure_ascii=False)}).lastrowid
        for asunto,tipo,descripcion,dias,estatus,cambio in DEMO_SOLICITUDES:
            solicitud={'asunto':asunto,'tipoApoyo':tipo,'descripcion':descripcion,
              'fechaRequerida':(date.today()-timedelta(days=dias-15)).isoformat(),'riesgoInmediato':False,
              'beneficiario':{'esTitular':True,'nombres':'','primerApellido':'','curp':''},
              'ubicacion':{'usaDomicilioRegistrado':True,'municipio':DEMO_PERFIL['municipio'],'codigoPostal':'64000',
                'colonia':'Centro','calle':'Calle Juárez','numero':'123'},
              'salud':{'seguridadSocial':'IMSS','tarjetaCuidarTuSalud':False,'gruposVulnerables':[]},
              'adjuntos':[],'usaContactoCuenta':True,'celularContacto':'','correoContacto':''}
            nueva=svc.crear(db,cid,svc.NuevaSolicitud(idempotencia=uuid.uuid4(),solicitud=solicitud))
            sid=int(nueva['folio'].split('#')[1])
            db.execute(text('''UPDATE Tbl_SolicitudesApoyo SET solapoyo_statusid=(SELECT id FROM Cat_StatusAtencion WHERE descripcion=:e),
              created=UTC_TIMESTAMP()-INTERVAL :d DAY, updated=UTC_TIMESTAMP()-INTERVAL :u DAY WHERE solapoyo_id=:id'''),
              {'e':estatus,'d':dias,'u':dias-cambio,'id':sid})
        db.commit()
    print(f'Cuenta demo lista: {DEMO_CORREO} con {len(DEMO_SOLICITUDES)} solicitudes.')


def borrar_ciudadano(args):
    from sqlalchemy.orm import Session
    from app.services import ciudadano_service as svc
    with Session(engine) as db:
        cid=db.execute(text('SELECT id FROM ciudadano_cuenta WHERE correo=:c'),{'c':args.correo.strip().lower()}).scalar()
        if not cid: raise SystemExit('No existe una cuenta del Ciudadano con ese correo.')
        total=svc.borrar_cuenta(db,cid)
        db.commit()
    print(f'Cuenta eliminada junto con {total} solicitud(es).')


if __name__=='__main__':
    parser=argparse.ArgumentParser()
    sub=parser.add_subparsers(dest='command',required=True)
    sub.add_parser('migrate')
    sub.add_parser('seed-wireframe')
    account=sub.add_parser('create-user')
    for key in ['correo','nombres','apellidos']:
        account.add_argument('--'+key,required=True)
    account.add_argument('--telefono',default='')
    account.add_argument('--entidad',default='19',help='Clave INEGI del estado autorizado')
    second_factor=sub.add_parser('setup-2fa')
    second_factor.add_argument('--correo',required=True)
    colonies=sub.add_parser('cargar-colonias',help='Importa el catálogo de códigos postales de SEPOMEX')
    colonies.add_argument('archivo')
    colonies.add_argument('--estado',default='19',help='Clave INEGI del estado; vacío para todos')
    colonies.add_argument('--codificacion',default='latin-1')
    demo=sub.add_parser('ciudadano-demo',help='Crea o restablece la cuenta demo del Ciudadano')
    demo.add_argument('--contrasena',default='SieasasDemo2026')
    erase=sub.add_parser('ciudadano-borrar',help='Elimina una cuenta del Ciudadano y sus solicitudes')
    erase.add_argument('--correo',required=True)
    args=parser.parse_args()
    if args.command=='migrate': migrate()
    elif args.command=='ciudadano-demo': demo_ciudadano(args)
    elif args.command=='ciudadano-borrar': borrar_ciudadano(args)
    elif args.command=='cargar-colonias': load_colonies(args)
    elif args.command=='seed-wireframe': seed()
    elif args.command=='setup-2fa': setup_2fa(args)
    else: provision(args)
