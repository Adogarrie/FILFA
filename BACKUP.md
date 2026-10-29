# Copias de seguridad de la base de datos

El plan gratuito de Supabase no incluye copias descargables. Por eso el workflow
[`.github/workflows/backup-supabase.yml`](.github/workflows/backup-supabase.yml)
hace un `pg_dump` **cada martes a las 09:00 UTC** y lo guarda **cifrado** como
artifact de GitHub durante **90 días** (unas 12 copias).

No usa la API REST, así que no gasta peticiones ni Log Ingest. Solo cuenta como
egress el tamaño del volcado, que son pocos MB a la semana.

## Qué contiene cada copia

`filfa-backup-AAAA-MM-DD.tar.gz.gpg` → al descifrarlo y descomprimirlo:

| Archivo | Contenido |
|---|---|
| `public.dump` | Esquema `public` completo: tablas, datos, funciones, triggers, políticas RLS y permisos. Formato custom de `pg_restore`. |
| `auth.dump` | Solo datos de `auth.users` y `auth.identities`, es decir, las cuentas de usuario de Supabase Auth. |
| `esquema_public.sql` | El esquema de `public` en SQL legible, para consultarlo sin restaurar nada. |

**No incluye:**
- **Storage**: la app ya no guarda archivos en Storage. Si en el futuro se vuelven a subir, no entrarían en la copia.
- **La configuración del proyecto**: proveedores de login (Google), URLs de redirección, claves y Edge Functions. Las funciones ya están en `supabase/functions/`.

## Puesta en marcha (una sola vez)

1. **Cadena de conexión.** En Supabase → botón **Connect** → **Session pooler**,
   copia la URI. Es de la forma:
   ```
   postgresql://postgres.<ref>:<password>@aws-0-<region>.pooler.supabase.com:5432/postgres
   ```
   - Sustituye `[YOUR-PASSWORD]` por la contraseña de la base de datos. Si no la
     recuerdas, se cambia en Project Settings → Database → *Reset database password*.
     La app no se ve afectada, porque usa la clave `anon`.
   - Usa el *Session pooler* y no la *Direct connection*: la directa es solo IPv6
     y los servidores de GitHub no la soportan.
2. **Secrets.** En GitHub → repo `FILFA` → Settings → Secrets and variables →
   Actions → *New repository secret*:
   - `SUPABASE_DB_URL`: la URI del paso anterior.
   - `BACKUP_PASSPHRASE`: una contraseña larga para cifrar las copias.
     **Guárdala en un gestor de contraseñas: si se pierde, las copias no se pueden abrir.**
3. **Primera copia.** Haz commit y push del workflow a la rama principal. Las
   ejecuciones programadas solo corren desde ahí. Luego ve a Actions →
   *Copia de seguridad Supabase* → **Run workflow** y comprueba que termina en verde.

## Descargar y abrir una copia

1. En GitHub → Actions → *Copia de seguridad Supabase* → elige una ejecución →
   sección **Artifacts** → descarga `filfa-backup-AAAA-MM-DD`. Se descarga un `.zip`.
2. Descomprime el zip, descifra la copia y extráela (en Git Bash, que ya trae `gpg`):
   ```bash
   gpg --decrypt -o filfa-backup.tar.gz filfa-backup-AAAA-MM-DD.tar.gz.gpg
   tar -xzf filfa-backup.tar.gz
   ```
   `gpg` te pedirá la contraseña (`BACKUP_PASSPHRASE`).

Para restaurar hace falta `pg_restore` 17. Hay dos formas de tenerlo:
- **Instalarlo:** el instalador de PostgreSQL 17 para Windows, marcando solo
  *Command Line Tools*.
- **Usar Docker** sin instalar nada:
  ```bash
  docker run --rm -it -v "$PWD:/b" -w /b postgres:17 bash
  ```

En los comandos siguientes, `$URL` es la cadena del Session pooler del proyecto
**destino**:
```bash
export URL='postgresql://postgres.<ref>:<password>@aws-0-<region>.pooler.supabase.com:5432/postgres'
```

## Comprobar una copia

Sin tocar ninguna base de datos:
```bash
pg_restore --list filfa-backup-AAAA-MM-DD/public.dump | grep 'TABLE DATA'
```
Conviene hacerlo de vez en cuando para confirmar que las copias se abren bien.

## Caso 1: recuperar una tabla (lo más habitual)

Por ejemplo, si se han borrado o estropeado filas de `clasificacion`.

1. **Genera el SQL de esa tabla** a partir de la copia. Esto no toca la base:
   ```bash
   pg_restore --data-only --table=clasificacion -f clasificacion.sql filfa-backup-AAAA-MM-DD/public.dump
   ```
2. **Revisa el archivo.** Después, en el **SQL Editor** de Supabase (o con
   `psql "$URL"`), sustituye el contenido dentro de una transacción:
   ```sql
   begin;
   delete from public.clasificacion;          -- o solo las filas afectadas
   -- pega aquí el contenido de clasificacion.sql (o \i clasificacion.sql en psql)
   commit;
   ```
   - Si algo falla antes del `commit`, haz `rollback;` y no habrá cambiado nada.
   - Si un trigger impide la carga (por ejemplo, las protecciones de predicción),
     añade `set local session_replication_role = replica;` justo después del `begin;`.
   - Si otras tablas tienen claves foráneas hacia la que borras, restaura también
     esas tablas, o borra solo las filas afectadas en lugar de toda la tabla.

## Caso 2: restaurar todo en un proyecto nuevo

Por ejemplo, si el proyecto original se ha perdido.

1. **Crea un proyecto nuevo** en Supabase, a ser posible con la misma versión de
   Postgres.
2. **Restaura primero los usuarios.** Las tablas de `public` apuntan a `auth.users`:
   ```bash
   pg_restore --dbname="$URL" --data-only filfa-backup-AAAA-MM-DD/auth.dump
   ```
3. **Restaura `public`:**
   ```bash
   pg_restore --dbname="$URL" --no-owner filfa-backup-AAAA-MM-DD/public.dump
   ```
   Los avisos del tipo *schema "public" already exists* o los referidos a
   extensiones se pueden ignorar. Revisa cualquier otro error.
4. **Reconfigura a mano** lo que no está en la copia:
   - Buckets de Storage, solo si se vuelven a usar.
   - Proveedor de Google y URLs de redirección (Authentication → Providers / URL Configuration).
   - Edge Functions: `supabase functions deploy`.
   - En `index.html`, las constantes `SUPABASE_URL` y `SUPABASE_ANON_KEY` del nuevo proyecto.

## Notas

- **Programación inactiva.** En un repo sin commits durante 60 días, GitHub
  desactiva las ejecuciones programadas y avisa por email. Se reactivan en
  Actions → el workflow → *Enable workflow*.
- **Proyecto en pausa.** La conexión semanal también cuenta como actividad, lo que
  ayuda a que Supabase no pause el proyecto gratuito por inactividad.
- **Cambiar la frecuencia.** Edita la línea `cron` del workflow; por ejemplo,
  `'0 4 * * *'` es a diario. Para cambiar cuánto tiempo se conservan las copias,
  edita `retention-days`.
