from sgsc_common.web import create_app
from sgsc_indicadores.routes import router

app = create_app('indicadores', 'SIEASAS Ejecutivo · Indicadores y Filtros',
                 'Consulta de indicadores, filtros y comparación de periodos.')
app.include_router(router)
