from sgsc_common.web import create_app
from sgsc_registro.routes import router

app = create_app('registro', 'SIEASAS Ejecutivo · Registro Ejecutivo',
                 'Registro de solicitudes desde el Ejecutivo con folio y origen de captura.')
app.include_router(router)
