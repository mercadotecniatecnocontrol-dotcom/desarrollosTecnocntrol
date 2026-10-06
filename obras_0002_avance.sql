-- =====================================================================
-- APP OBRAS — 0002: % de avance calculado en la base de datos
-- Correr DESPUÉS de obras_0001_esquema.sql
-- =====================================================================

-- % de avance por partida y general ('*'), ponderado por importe.
-- Así todos (residentes incluidos) ven el MISMO porcentaje sin ver precios.
create or replace function public.obra_avance(p_obra uuid)
returns table(partida text, avance numeric, conceptos integer, terminados integer)
language sql stable security definer set search_path = public as $$
  with base as (
    select c.partida,
           greatest(c.avance_pct,
                    case when c.cantidad > 0 then least(100, c.cantidad_ejecutada / c.cantidad * 100) else 0 end) as av,
           case when p.sin_importe then 0 else coalesce(p.importe, 0) end as imp
    from public.obra_conceptos c
    left join public.obra_precios p on p.obra_id = c.obra_id and p.clave = c.clave
    where c.obra_id = p_obra and not c.es_grupo and public.obra_puede_ver(p_obra)
  ), par as (
    select b.partida,
           case when sum(b.imp) > 0 then sum(b.av * b.imp) / sum(b.imp) else avg(b.av) end as avance,
           sum(b.imp) as peso,
           count(*)::int as conceptos,
           (count(*) filter (where b.av >= 100))::int as terminados
    from base b group by b.partida
  )
  select par.partida, round(par.avance, 2), par.conceptos, par.terminados from par
  union all
  select '*',
         round(case when sum(par.peso) > 0 then sum(par.avance * par.peso) / sum(par.peso) else avg(par.avance) end, 2),
         sum(par.conceptos)::int, sum(par.terminados)::int
  from par having count(*) > 0;
$$;
revoke execute on function public.obra_avance(uuid) from public, anon;
grant execute on function public.obra_avance(uuid) to authenticated;

-- Al BORRAR una evidencia, recalcular la cantidad ejecutada del concepto
create or replace function public.obra_evidencia_borrada() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  update public.obra_conceptos c set
    cantidad_ejecutada = coalesce((select sum(e.cantidad) from public.obra_evidencias e
                                   where e.obra_id = old.obra_id and e.concepto_clave = old.concepto_clave), 0),
    actualizado_en = now()
  where c.obra_id = old.obra_id and c.clave = old.concepto_clave;
  return old;
end $$;
revoke execute on function public.obra_evidencia_borrada() from public, anon;

drop trigger if exists trg_obra_evid_borrada on public.obra_evidencias;
create trigger trg_obra_evid_borrada after delete on public.obra_evidencias
  for each row execute function public.obra_evidencia_borrada();

-- Índices para que las listas carguen rápido con muchas evidencias
create index if not exists obra_evidencias_concepto on public.obra_evidencias (obra_id, concepto_clave);
create index if not exists obra_miembros_email on public.obra_miembros (email);
