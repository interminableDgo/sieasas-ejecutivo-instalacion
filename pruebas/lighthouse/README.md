# Evaluación con Lighthouse

Lighthouse 13.6.0 evalúa la calidad externa de la aplicación web Ejecutiva: rendimiento,
accesibilidad, buenas prácticas y SEO. Se mide la pantalla de inicio de sesión
(`https://127.0.0.1:5173/`), que es la entrada de la aplicación, en dos perfiles:

- **Celular** (`--form-factor=mobile`): Moto G Power emulado, red 4G lenta y CPU 4 veces más lenta.
- **Computadora** (`--preset=desktop`).

Cada perfil se corre tres veces y se reporta la mediana de rendimiento.

## Cómo repetir la medición

1. Compilar la app: `cd sgsc_ejecutiva; flutter build web --release -O4 --dart-define=API_BASE_URL=http://127.0.0.1:8000`
2. Servirla: `cd backend; .venv\Scripts\python.exe serve_web.py`
3. Medir: `.\pruebas\lighthouse\ejecutar_lighthouse.ps1 -Modo mobile` y `-Modo desktop`.
   Los reportes quedan en `reportes/ultima/` (ignorada por Git).

## Prueba de punta a punta del inicio de sesión

`login_html_e2e.mjs` comprueba en Microsoft Edge el inicio de sesión HTML y su traspaso a
Flutter: que Flutter no se descargue sin interacción, que se pueda escribir con Flutter cargado
detrás, que al enviar Flutter consulte la API y que los enlaces abran la pantalla correcta.
Requiere además la API en `http://127.0.0.1:8000`.

## Reportes guardados

| Carpeta | Fecha | Celular | Computadora |
|---|---|---|---|
| `reportes/inicial/` | 17/11/2026, una corrida | Rend. 27 · Acc. 100 · BP 81 · SEO 100 | Rend. 59 · Acc. 100 · BP 81 · SEO 100 |
| `reportes/final/` | 18/11/2026, tres corridas | 100 · 100 · 100 · 100 | 100 · 100 · 100 · 100 |

Los reportes `.html` se abren en cualquier navegador.
