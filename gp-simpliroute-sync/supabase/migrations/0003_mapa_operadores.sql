-- =====================================================================
-- Grupo Portátil · Puente SimpliRoute → Supabase
-- 0003_mapa_operadores.sql — Quién es quién
-- =====================================================================
-- APLICADA a gp-inventario el 2026-08-19.
--
-- La correspondencia driver de SimpliRoute -> operador de GP no se puede
-- deducir de los datos (7 drivers contra 5 operadores registrados). La dio
-- Eduardo. Se deja en migración para que sea reproducible y auditable.
-- =====================================================================

-- Manuel es Meñito: NO se crea operador nuevo, se le pone el nombre real al
-- que ya existía y el apodo queda como alias (que es como lo conocen).
update operadores
   set nombre = 'Manuel',
       alias  = 'Meñito',
       notas  = trim(coalesce(notas,'') || ' Manuel = Meñito (confirmado por Eduardo 2026-08-19).')
 where id = 3;

-- Christian hace movimientos (entregas y bajas), no ruta fija de limpieza.
-- Se da de alta como operador propio y NO se reusa el comodín "Extra" (id 5),
-- que está marcado como cobertura temporal y no como persona fija.
insert into operadores (nombre, alias, activo, notas)
select 'Christian', 'Christian', true,
       'Entregas y bajas (movimientos), no ruta fija de limpieza. Alta 2026-08-19 desde SimpliRoute.'
where not exists (select 1 from operadores where upper(nombre) = 'CHRISTIAN');

-- El mapa. Los dos drivers de Querétaro quedan sin operador a propósito:
-- QRO se lleva aparte y no existe esa sucursal en la base.
update simpliroute_operadores set operador_id = 3,
       notas = 'Manuel (Meñito) — ruta grande MTY'   where driver_id = '385815';
update simpliroute_operadores set operador_id = 2,
       notas = 'Juan Pablo — ruta grande MTY'        where driver_id = '309312';
update simpliroute_operadores set operador_id = 1,
       notas = 'Emmanuel — ruta grande MTY'          where driver_id = '309311';
update simpliroute_operadores set operador_id = 4,
       notas = 'Alberto — fosas / pipa'              where driver_id = '324472';
update simpliroute_operadores set
       operador_id = (select id from operadores where upper(nombre) = 'CHRISTIAN'),
       notas = 'Christian — entregas y bajas'        where driver_id = '309316';
update simpliroute_operadores set operador_id = null,
       notas = 'Querétaro — se lleva aparte, sin operador de GP'
 where driver_id in ('376983','327288');

-- Reprocesar para que los servicios ya cargados tomen el operador:
--   select * from simpliroute_promover('2026-08-18');
--
-- Resultado 2026-08-18 — los 86 servicios con operador, ninguno sin asignar:
--   Meñito 25 · Emmanuel 25 · Juan Pablo 25 · Alberto 6 · Christian 5
--
-- OJO al leer estos números: Alberto hizo además 7 fosas que el modelo de
-- datos todavía no representa, y los 5 de Christian son retiros, no ruta.
-- Compararlos contra los 25 de una ruta de limpieza sería engañoso.
