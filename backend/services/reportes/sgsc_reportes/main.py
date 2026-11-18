from sgsc_common.web import create_app
from sgsc_reportes.routes import router

app = create_app('reportes', 'SIEASAS Ejecutivo · Reportes y Exportación',
                 'Exportación en Excel y PDF de la información filtrada, solo con agregados.')
app.include_router(router)
