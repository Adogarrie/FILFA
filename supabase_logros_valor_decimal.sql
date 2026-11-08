-- ═══════════════════════════════════════════════════════════════
-- FILFA — Logros: `valor` admite decimales
--
-- `logros.valor` era integer, pero algunos logros guardan un valor con
-- decimales (edad media de la plantilla en Guardería / Plantilla
-- veterana, p. ej. 27.3). Como recalcularLogros (index.html) inserta
-- todos los logros nuevos en una sola petición, un único valor decimal
-- hacía fallar el lote entero: ningún logro de ese recálculo se guardaba
-- ni se anunciaba en el tablón.
--
-- Los logros que no se pudieron guardar se conceden en el siguiente
-- recálculo (Admin → Liga FILFA → "🏆 Recalcular logros").
--
-- Ejecutar en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════════════════════

alter table logros alter column valor type numeric using valor::numeric;
