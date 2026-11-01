// FILFA — Edge Function puntos-laliga
//
// Intermediario con la API pública (no documentada) de LaLiga Fantasy, que
// no admite llamadas desde el navegador (no envía cabeceras CORS). Puntos y
// catálogo salen de una sola petición (competition/1/players), guardada 10
// minutos en memoria para no repetir descargas; los minutos, de la ficha de
// cada jugador. No escribe en la base de datos: la app guarda los puntos y
// los "no jugó" con los permisos de siempre.
//
// Cuerpo (POST, JSON):
//   { accion: 'puntos', jornada: 10 } → { jornada, puntos: [[lf_id, team_id, posicion, pts], ...] }
//       solo los jugadores con puntos en esa jornada (los de equipos que ya han jugado)
//   { accion: 'catalogo' } → { jugadores: [{ id, n, t, p, s, v }, ...] }
//       id, nombre, equipo (teamId), posición (1 POR, 2 DEF, 3 MED, 4 DEL), estado y valor
//   { accion: 'minutos', jornada: 10, ids: ['68', ...] } → { minutos: { '68': 90, ... } }
//       minutos jugados en esa jornada según la ficha de cada jugador
//       (competition/1/player/{id}, una petición por jugador, con pausas);
//       null = la ficha no tiene esa jornada (no convocado o aún sin jugar).
//       Máximo MAX_IDS por llamada: la app las reparte en bloques.
//
// Solo para usuarios con sesión iniciada (el token lo verifica Supabase antes
// de llegar aquí; se comprueba además que no sea la clave anónima).
//
// Desplegar: Supabase Dashboard → Edge Functions → Deploy a new function →
// "Via Editor", nombre puntos-laliga, pegar este archivo. O con la CLI:
//   supabase functions deploy puntos-laliga

const API = 'https://fantasy-api.llt-services.com/api/v1/competition/1/players';
const API_FICHA = 'https://fantasy-api.llt-services.com/api/v1/competition/1/player/';
const CACHE_MS = 10 * 60 * 1000;
const CACHE_FICHA_MS = 2 * 60 * 1000;
const PAUSA_MS = 150;   // entre peticiones de fichas, para no saturar la API
const MAX_IDS = 40;

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

// deno-lint-ignore no-explicit-any
let cache: { t: number; datos: any[] } | null = null;

async function catalogo() {
  if (cache && Date.now() - cache.t < CACHE_MS) return cache.datos;
  const r = await fetch(API, { headers: { Accept: 'application/json' } });
  if (!r.ok) throw new Error(`LaLiga Fantasy respondió ${r.status}`);
  const datos = await r.json();
  if (!Array.isArray(datos)) throw new Error('LaLiga Fantasy ha cambiado el formato de sus datos');
  cache = { t: Date.now(), datos };
  return datos;
}

// Ficha de un jugador: minutos por jornada { [jornada]: minutos }.
const cacheFichas = new Map<string, { t: number; minutos: Record<number, number> }>();
const esperar = (ms: number) => new Promise((r) => setTimeout(r, ms));

async function minutosDe(id: string) {
  const c = cacheFichas.get(id);
  if (c && Date.now() - c.t < CACHE_FICHA_MS) return c.minutos;
  await esperar(PAUSA_MS);
  const r = await fetch(API_FICHA + encodeURIComponent(id), { headers: { Accept: 'application/json' } });
  if (!r.ok) throw new Error(`LaLiga Fantasy respondió ${r.status} con la ficha del jugador ${id}`);
  const ficha = await r.json();
  if (!Array.isArray(ficha?.playerStats)) throw new Error('LaLiga Fantasy ha cambiado el formato de las fichas');
  const minutos: Record<number, number> = {};
  for (const s of ficha.playerStats) {
    const m = s?.stats?.mins_played;
    minutos[Number(s.weekNumber)] = Number(Array.isArray(m) ? m[0] : m) || 0;
  }
  cacheFichas.set(id, { t: Date.now(), minutos });
  return minutos;
}

function rolDelToken(req: Request): string | null {
  const token = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '');
  try {
    const b = token.split('.')[1].replace(/-/g, '+').replace(/_/g, '/');
    return JSON.parse(atob(b + '==='.slice((b.length + 3) % 4))).role ?? null;
  } catch {
    return null;
  }
}

const json = (cuerpo: unknown, status = 200) =>
  new Response(JSON.stringify(cuerpo), { status, headers: { ...CORS, 'Content-Type': 'application/json' } });

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  if (req.method !== 'POST') return json({ error: 'Método no permitido' }, 405);
  if (rolDelToken(req) !== 'authenticated') return json({ error: 'Inicia sesión para usar esta función' }, 401);

  try {
    const { accion, jornada, ids } = await req.json().catch(() => ({}));
    if (accion === 'minutos') {
      const j = Number(jornada);
      if (!Number.isInteger(j) || j < 1 || j > 38) return json({ error: 'Jornada no válida' }, 400);
      if (!Array.isArray(ids) || ids.length > MAX_IDS || !ids.every((x) => /^\d{1,9}$/.test(String(x))))
        return json({ error: `Lista de jugadores no válida (máximo ${MAX_IDS})` }, 400);
      const minutos: Record<string, number | null> = {};
      for (const id of new Set(ids.map(String))) minutos[id] = (await minutosDe(id))[j] ?? null;
      return json({ jornada: j, minutos });
    }
    if (accion === 'puntos') {
      const j = Number(jornada);
      if (!Number.isInteger(j) || j < 1 || j > 38) return json({ error: 'Jornada no válida' }, 400);
      const puntos = [];
      for (const p of await catalogo()) {
        const w = (p.weekPoints || []).find((x: { weekNumber: unknown }) => Number(x.weekNumber) === j);
        if (w) puntos.push([String(p.id), String(p.teamId), Number(p.positionId), Number(w.points) || 0]);
      }
      return json({ jornada: j, puntos });
    }
    if (accion === 'catalogo') {
      const jugadores = (await catalogo())
        .filter((p) => Number(p.positionId) >= 1 && Number(p.positionId) <= 4) // sin entrenadores
        .map((p) => ({ id: String(p.id), n: p.nickname, t: String(p.teamId), p: Number(p.positionId),
                       s: p.playerStatus, v: Number(p.marketValue) || 0 }));
      return json({ jugadores });
    }
    return json({ error: 'Acción no válida' }, 400);
  } catch (e) {
    return json({ error: (e as Error)?.message || String(e) }, 502);
  }
});
