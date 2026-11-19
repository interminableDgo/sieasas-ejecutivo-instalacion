// Prueba de punta a punta del inicio de sesión HTML (web/index.html) y su traspaso a Flutter,
// emulando un celular Android en Microsoft Edge. Cubre lo que flutter test no puede ejecutar
// porque solo existe en el navegador (lib/services/html_login_web.dart).
//
// Requisitos: la app servida con serve_web.py en https://127.0.0.1:5173 y la API en
// http://127.0.0.1:8000 con CORS_ORIGINS que incluya https://127.0.0.1:5173.
//   npm install --no-save puppeteer-core@25
//   node pruebas/lighthouse/login_html_e2e.mjs
import puppeteer from 'puppeteer-core';

const URL = process.env.APP_URL ?? 'https://127.0.0.1:5173/';
const EDGE = process.env.CHROME_PATH ?? 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe';
const espera = (ms) => new Promise((r) => setTimeout(r, ms));
let fallas = 0;
const revisar = (ok, texto) => { console.log(`${ok ? 'OK   ' : 'FALLA'} ${texto}`); if (!ok) fallas++; };

const navegador = await puppeteer.launch({
  executablePath: EDGE, headless: true, acceptInsecureCerts: true, args: ['--ignore-certificate-errors'],
});
async function abrir() {
  const p = await navegador.newPage();
  await p.setUserAgent('Mozilla/5.0 (Linux; Android 11; moto g power (2022)) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/157.0.0.0 Mobile Safari/537.36');
  await p.setViewport({ width: 412, height: 823, deviceScaleFactor: 1, isMobile: true, hasTouch: true });
  p.pedidos = [];
  p.on('request', (r) => p.pedidos.push(r.url()));
  await p.goto(URL, { waitUntil: 'load' });
  return p;
}

// 1) Sin interacción la página no descarga Flutter.
let p = await abrir();
await espera(4000);
revisar(!p.pedidos.some((u) => u.includes('main.dart.js')), 'sin interacción no se descarga main.dart.js');

// 2) Tocar un campo descarga Flutter; el formulario HTML sigue funcionando.
await p.tap('#correo');
await espera(9000);
revisar(p.pedidos.some((u) => u.includes('main.dart.js')), 'al tocar el campo se descarga Flutter');
revisar(await p.$('#carga') !== null, 'el formulario HTML sigue visible con Flutter cargado');
await p.type('#correo', 'noexiste@example.com');
await p.tap('#clave');
await p.type('#clave', 'Una clave equivocada');
const [correo, clave, contador] = await p.evaluate(() => [
  document.getElementById('correo').value, document.getElementById('clave').value,
  document.getElementById('contador').textContent,
]);
revisar(correo === 'noexiste@example.com' && clave === 'Una clave equivocada' && contador === '20/150',
  'se escribe en el HTML con Flutter cargado detrás');
await p.tap('#ojo');
revisar(await p.$eval('#clave', (e) => e.type) === 'text', 'el botón del ojo muestra la contraseña');
await p.tap('#ojo');

// 3) Al enviar, Flutter recibe los datos, consulta la API y toma la pantalla.
await p.tap('.boton');
await espera(5000);
revisar(await p.$('#carga') === null, 'después de enviar, Flutter muestra su pantalla');
revisar(await p.evaluate(() => window.siesasLogin.entrada) === null, 'la contraseña no queda en la página');
await p.close();

// 4) Un enlace presionado antes de que cargue Flutter abre la pantalla correspondiente.
p = await abrir();
await espera(1500);
await p.type('#correo', 'alguien@example.com');
await p.tap('[data-modo="recover"]');
revisar(await p.$eval('#acceso', (f) => f.getAttribute('aria-busy')) === 'true', 'el formulario indica que está cargando');
await espera(10000);
revisar(await p.$('#carga') === null, 'Flutter abrió la recuperación de contraseña');

await navegador.close();
console.log(fallas ? `${fallas} comprobaciones fallaron` : 'Todas las comprobaciones pasaron');
process.exit(fallas ? 1 : 0);
