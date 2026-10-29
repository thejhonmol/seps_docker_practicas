CREATE SCHEMA IF NOT EXISTS seps;
CREATE TABLE IF NOT EXISTS seps.importaciones (
 id BIGSERIAL PRIMARY KEY,
 origen TEXT NOT NULL,
 iniciado TIMESTAMPTZ NOT NULL DEFAULT now(),
 finalizado TIMESTAMPTZ,
 registros_leidos INTEGER NOT NULL DEFAULT 0,
 registros_validos INTEGER NOT NULL DEFAULT 0,
 registros_rechazados INTEGER NOT NULL DEFAULT 0,
 estado TEXT NOT NULL DEFAULT 'iniciada'
);
CREATE TABLE IF NOT EXISTS seps.organizaciones (
 fecha_corte DATE NOT NULL,
 ruc VARCHAR(13) NOT NULL,
 razon_social TEXT NOT NULL,
 estado_juridico TEXT,
 sector TEXT,
 tipo TEXT,
 grupo TEXT,
 clase TEXT,
 subclase TEXT,
 provincia TEXT,
 canton TEXT,
 parroquia TEXT,
 codigo_parroquia TEXT,
 numero_organizaciones INTEGER NOT NULL DEFAULT 1 CHECK(numero_organizaciones>=0),
 actualizado TIMESTAMPTZ NOT NULL DEFAULT now(),
 PRIMARY KEY(fecha_corte,ruc)
);
CREATE INDEX IF NOT EXISTS idx_org_provincia ON seps.organizaciones(provincia);
CREATE INDEX IF NOT EXISTS idx_org_sector ON seps.organizaciones(sector);
CREATE INDEX IF NOT EXISTS idx_org_fecha ON seps.organizaciones(fecha_corte);
CREATE TABLE IF NOT EXISTS seps.rechazos (
 id BIGSERIAL PRIMARY KEY,
 importacion_id BIGINT REFERENCES seps.importaciones(id),
 fila INTEGER NOT NULL,
 motivo TEXT NOT NULL,
 raw TEXT,
 creado TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE OR REPLACE VIEW seps.v_resumen_provincias AS
 SELECT fecha_corte,provincia,sector,estado_juridico,COUNT(*) AS organizaciones
 FROM seps.organizaciones GROUP BY fecha_corte,provincia,sector,estado_juridico;
CREATE OR REPLACE VIEW seps.v_indicadores AS
 SELECT fecha_corte, COUNT(*) AS organizaciones,
 COUNT(DISTINCT provincia) FILTER(WHERE provincia NOT IN ('NO DEFINIDO','ZONA NO DELIMITADA')) AS provincias,
 COUNT(*) FILTER (WHERE estado_juridico='ACTIVA') AS activas
 FROM seps.organizaciones GROUP BY fecha_corte;
