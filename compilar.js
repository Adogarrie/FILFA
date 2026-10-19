/*
 * Compila index.html para producción (lo ejecuta Vercel al desplegar).
 *
 * index.html sigue siendo el ÚNICO archivo que se edita: lleva el código de
 * la app en un <script type="text/babel"> y carga Babel standalone, así que
 * abierto en local funciona igual que siempre (compilando en el navegador).
 *
 * Al desplegar, este script genera dist/ con:
 *   - dist/index.html: el mismo HTML, con el JSX ya compilado a JS normal y
 *     sin la etiqueta de Babel (unos 3 MB menos de descarga y sin los varios
 *     segundos de compilación en el navegador de cada usuario).
 *   - Solo los archivos que usa la página: manifest.json, sw.js, icons/,
 *     escudos/ y nations/. (Antes se publicaba la carpeta entera, con los
 *     .sql, los scripts de Python, etc.)
 *
 * Usa las MISMAS opciones que aplica Babel standalone a <script type="text/babel">
 * (presets react + env y sus tres plugins por defecto) y la misma versión
 * (fijada en package.json), para que el código resultante se comporte igual
 * que el compilado en el navegador.
 *
 * Si algo no cuadra (no encuentra el script, falla la compilación...) termina
 * con error y Vercel cancela el despliegue: la versión publicada no cambia.
 *
 * Uso:   node compilar.js                (index.html → dist/)
 *        node compilar.js entrada.html dir_salida
 * Babel: se toma de node_modules (@babel/standalone). Para probar sin npm se
 *        puede indicar la ruta de un babel.min.js con BABEL_STANDALONE=ruta.
 */
const fs = require('fs');
const path = require('path');

const raiz    = __dirname;
const entrada = path.resolve(raiz, process.argv[2] || 'index.html');
const salida  = path.resolve(raiz, process.argv[3] || 'dist');
const ASSETS  = ['manifest.json', 'sw.js', 'icons', 'escudos', 'nations'];
const ETIQUETA_BABEL = '<script src="https://unpkg.com/@babel/standalone/babel.min.js"></script>';

function fallar(msg) {
  console.error(`\n✖ compilar.js: ${msg}\n`);
  process.exit(1);
}

const Babel = (() => {
  try { return require(process.env.BABEL_STANDALONE ? path.resolve(process.env.BABEL_STANDALONE) : '@babel/standalone'); }
  catch (e) { fallar(`no se encuentra Babel standalone (${e.message}). Ejecuta "npm install" o define BABEL_STANDALONE.`); }
})();

let html = fs.readFileSync(entrada, 'utf8');

// 1. Exactamente un bloque <script type="text/babel">.
const bloques = [...html.matchAll(/<script type="text\/babel">([\s\S]*?)<\/script>/g)];
if (bloques.length !== 1) fallar(`se esperaba 1 <script type="text/babel"> y hay ${bloques.length}.`);

// 2. Compilar con las opciones por defecto de Babel standalone para text/babel.
let codigo;
try {
  codigo = Babel.transform(bloques[0][1], {
    filename: 'index.html',
    presets: ['react', 'env'],
    plugins: ['transform-class-properties', 'transform-object-rest-spread', 'transform-flow-strip-types'],
    comments: false,     // los comentarios no afectan al comportamiento y pesan
    sourceMaps: false,   // en el navegador se generaba un source map inline (duplicaba el tamaño)
  }).code;
} catch (e) {
  fallar(`error al compilar el JSX:\n${e.message}`);
}
// Un "</script" dentro del JS cerraría la etiqueta antes de tiempo.
codigo = codigo.replace(/<\/script/gi, '<\\/script');

// 3. Quitar la carga de Babel y sustituir el bloque por el JS compilado.
if (!html.includes(ETIQUETA_BABEL)) fallar('no se encuentra la etiqueta de Babel standalone en el <head>.');
html = html.replace(ETIQUETA_BABEL + '\n', '').replace(ETIQUETA_BABEL + '\r\n', '').replace(ETIQUETA_BABEL, '');
html = html.replace(bloques[0][0], () => `<script>\n${codigo}\n</script>`);
if (html.includes('text/babel') || html.includes('babel.min.js')) fallar('quedan restos de Babel en el HTML compilado.');

// 4. Escribir dist/ desde cero con el HTML y los archivos que usa la página.
fs.rmSync(salida, { recursive: true, force: true });
fs.mkdirSync(salida, { recursive: true });
fs.writeFileSync(path.join(salida, 'index.html'), html);
for (const a of ASSETS) {
  const origen = path.join(path.dirname(entrada), a);
  if (!fs.existsSync(origen)) fallar(`falta ${a}, que la página necesita.`);
  fs.cpSync(origen, path.join(salida, a), { recursive: true });
}

const kb = n => `${Math.round(n / 1024)} KB`;
console.log(`✔ ${path.relative(raiz, entrada)} → ${path.relative(raiz, salida) || '.'}/index.html`);
console.log(`  JSX compilado: ${kb(Buffer.byteLength(bloques[0][1]))} → ${kb(Buffer.byteLength(codigo))} · HTML final: ${kb(Buffer.byteLength(html))}`);
console.log(`  Copiados: ${ASSETS.join(', ')}`);
