from sgsc_common.web import create_app
from sgsc_detalle.routes import router

app = create_app('detalle', 'SIEASAS Ejecutivo · Detalle de Indicadores',
                 'Solicitudes que conforman un indicador y detalle de cada una.')
app.include_router(router)
