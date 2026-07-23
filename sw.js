const CACHE = 'filfa-v7';
const SHELL = ['/index.html', '/'];

// Instalar: pre-cachear el shell de la app
self.addEventListener('install', e => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(SHELL)));
  self.skipWaiting();
});

// Activar: limpiar cachés antiguas
self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys().then(keys =>
      Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)))
    )
  );
  self.clients.claim();
});

// Fetch: network-first para el shell; ignorar llamadas a Supabase y CDNs
self.addEventListener('fetch', e => {
  const url = new URL(e.request.url);

  // Dejar pasar sin interceptar: Supabase API, CDNs externos, no-GET
  if (e.request.method !== 'GET') return;
  if (url.hostname.includes('supabase.co')) return;
  if (url.hostname.includes('unpkg.com')) return;
  if (url.hostname.includes('cdn.')) return;

  e.respondWith(
    fetch(e.request)
      .then(res => {
        // Actualizar caché con la respuesta fresca
        const clone = res.clone();
        caches.open(CACHE).then(c => c.put(e.request, clone));
        return res;
      })
      .catch(() => caches.match(e.request))
  );
});
