-- Native PostgreSQL ingestion; callable as SELECT * FROM seps.cargar_organizaciones().
-- Source is read-only inside the postgres container at /seps-data/2026.txt.
CREATE TABLE IF NOT EXISTS seps.organizaciones_raw (
 fecha_corte TEXT, estado_juridico TEXT, sector TEXT, tipo TEXT, grupo TEXT,
 clase TEXT, subclase TEXT, provincia TEXT, canton TEXT, parroquia TEXT,
 numero_organizaciones TEXT, codigo_parroquia TEXT, razon_social TEXT, ruc TEXT
);

CREATE OR REPLACE FUNCTION seps.cargar_organizaciones()
RETURNS TABLE(importacion_id BIGINT, leidos BIGINT, validos BIGINT, rechazados BIGINT)
LANGUAGE plpgsql AS $$
DECLARE v_id BIGINT;
DECLARE v_leidos BIGINT;
DECLARE v_rechazados BIGINT;
DECLARE v_validos BIGINT;
BEGIN
  INSERT INTO seps.importaciones(origen)
  VALUES ('SEPS 2026 / PostgreSQL COPY orquestado por n8n')
  RETURNING id INTO v_id;
  TRUNCATE seps.organizaciones_raw;
  EXECUTE $copy$COPY seps.organizaciones_raw
    FROM '/seps-data/2026.txt'
    WITH (FORMAT csv, DELIMITER E'\t', HEADER true, QUOTE '"', ENCODING 'UTF8')$copy$;
  SELECT count(*) INTO v_leidos FROM seps.organizaciones_raw;
  INSERT INTO seps.rechazos(importacion_id,fila,motivo,raw)
  SELECT v_id,row_number() OVER ()::INTEGER+1,
    'RUC, fecha o razón social no válido',
    concat_ws(' / ',fecha_corte,razon_social,ruc)
  FROM seps.organizaciones_raw
  WHERE NOT (trim(coalesce(ruc,'')) ~ '^[0-9]{13}$'
    AND trim(coalesce(fecha_corte,'')) ~ '^20[0-9]{2}-[0-9]{1,2}-[0-9]{1,2}$'
    AND nullif(trim(coalesce(razon_social,'')),'') IS NOT NULL
    AND coalesce(numero_organizaciones,'') ~ '^[0-9]+$');
  GET DIAGNOSTICS v_rechazados = ROW_COUNT;
  INSERT INTO seps.organizaciones
   (fecha_corte,estado_juridico,sector,tipo,grupo,clase,subclase,provincia,
    canton,parroquia,numero_organizaciones,codigo_parroquia,razon_social,ruc)
  SELECT to_date(trim(fecha_corte),'YYYY-MM-DD'),
    upper(btrim(estado_juridico)),upper(btrim(sector)),upper(btrim(tipo)),
    upper(btrim(grupo)),upper(btrim(clase)),upper(btrim(subclase)),
    upper(btrim(provincia)),upper(btrim(canton)),upper(btrim(parroquia)),
    numero_organizaciones::INTEGER,btrim(codigo_parroquia),btrim(razon_social),
    btrim(ruc)
  FROM seps.organizaciones_raw
  WHERE trim(coalesce(ruc,'')) ~ '^[0-9]{13}$'
    AND trim(coalesce(fecha_corte,'')) ~ '^20[0-9]{2}-[0-9]{1,2}-[0-9]{1,2}$'
    AND nullif(trim(coalesce(razon_social,'')),'') IS NOT NULL
    AND coalesce(numero_organizaciones,'') ~ '^[0-9]+$'
  ON CONFLICT (fecha_corte,ruc) DO UPDATE SET
    razon_social = excluded.razon_social,
    estado_juridico = excluded.estado_juridico,
    sector = excluded.sector,
    tipo = excluded.tipo,
    grupo = excluded.grupo,
    clase = excluded.clase,
    subclase = excluded.subclase,
    provincia = excluded.provincia,
    canton = excluded.canton,
    parroquia = excluded.parroquia,
    numero_organizaciones = excluded.numero_organizaciones,
    codigo_parroquia = excluded.codigo_parroquia,
    actualizado = now();
  GET DIAGNOSTICS v_validos = ROW_COUNT;
  UPDATE seps.importaciones
    SET estado='finalizada',finalizado=now(),
        registros_leidos=v_leidos::INTEGER,
        registros_validos=v_validos::INTEGER,
        registros_rechazados=v_rechazados::INTEGER
    WHERE id=v_id;
  importacion_id := v_id;
  leidos := v_leidos;
  validos := v_validos;
  rechazados := v_rechazados;
  RETURN NEXT;
END $$;
