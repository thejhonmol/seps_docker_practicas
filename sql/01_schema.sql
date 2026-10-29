-- Nuevo esquema independiente: no elimina datos anteriores ni tablas de n8n.
CREATE SCHEMA IF NOT EXISTS seps_fin;
CREATE TABLE IF NOT EXISTS seps_fin.importaciones (
 id BIGSERIAL PRIMARY KEY,
 origen TEXT NOT NULL,
 sha256 TEXT NOT NULL,
 iniciado TIMESTAMPTZ NOT NULL DEFAULT now(),
 finalizado TIMESTAMPTZ,
 registros_leidos INTEGER NOT NULL DEFAULT 0,
 registros_validos INTEGER NOT NULL DEFAULT 0,
 registros_observados INTEGER NOT NULL DEFAULT 0,
 estado TEXT NOT NULL DEFAULT 'iniciada',
 error TEXT
);
CREATE TABLE IF NOT EXISTS seps_fin.valores (
 fecha_corte DATE NOT NULL,
 segmento TEXT NOT NULL,
 entidad TEXT NOT NULL,
 es_total BOOLEAN NOT NULL DEFAULT FALSE,
 tipo TEXT NOT NULL CHECK (tipo IN ('cuenta','indicador')),
 codigo TEXT NOT NULL,
 nombre TEXT NOT NULL,
 unidad TEXT NOT NULL CHECK (unidad IN ('USD','proporcion','numero')),
 valor NUMERIC,
 estado TEXT NOT NULL CHECK (estado IN ('valido','sin_dato','error_excel','no_numerico')),
 archivo TEXT NOT NULL,
 hoja TEXT NOT NULL,
 celda TEXT NOT NULL,
 importacion_id BIGINT NOT NULL REFERENCES seps_fin.importaciones(id),
 PRIMARY KEY (fecha_corte, segmento, entidad, tipo, codigo),
 CHECK ((estado='valido' AND valor IS NOT NULL) OR (estado<>'valido' AND valor IS NULL))
);
CREATE TABLE IF NOT EXISTS seps_fin.observaciones (
 id BIGSERIAL PRIMARY KEY,
 importacion_id BIGINT NOT NULL REFERENCES seps_fin.importaciones(id),
 archivo TEXT NOT NULL,
 hoja TEXT NOT NULL,
 celda TEXT NOT NULL,
 motivo TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS valores_tipo_codigo ON seps_fin.valores(tipo,codigo,fecha_corte);
CREATE INDEX IF NOT EXISTS valores_segmento ON seps_fin.valores(segmento,entidad);
-- Sin totales de grupo ni sumas entre cuentas padre/hijas.
CREATE OR REPLACE VIEW seps_fin.v_balance AS
SELECT fecha_corte,segmento,entidad,
 MAX(valor) FILTER(WHERE codigo='1') AS activos,
 MAX(valor) FILTER(WHERE codigo='2') AS pasivos,
 MAX(valor) FILTER(WHERE codigo='3') AS patrimonio,
 MAX(valor) FILTER(WHERE codigo='4') AS gastos,
 MAX(valor) FILTER(WHERE codigo='5') AS ingresos
FROM seps_fin.valores WHERE tipo='cuenta' AND NOT es_total
GROUP BY fecha_corte,segmento,entidad;
CREATE OR REPLACE VIEW seps_fin.v_indicadores AS
SELECT fecha_corte,segmento,entidad,nombre,valor,unidad,estado,
 CASE WHEN unidad='proporcion' THEN valor*100 ELSE valor END AS valor_presentacion
FROM seps_fin.valores WHERE tipo='indicador' AND NOT es_total;
CREATE OR REPLACE VIEW seps_fin.v_control AS
SELECT fecha_corte,segmento,COUNT(*) AS celdas,
 COUNT(*) FILTER(WHERE estado='valido') AS validas,
 COUNT(*) FILTER(WHERE estado<>'valido') AS observadas,
 COUNT(DISTINCT entidad) FILTER(WHERE NOT es_total) AS entidades
FROM seps_fin.valores GROUP BY fecha_corte,segmento;
