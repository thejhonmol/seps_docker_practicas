# Prácticas preprofesionales: SEPS + Docker + n8n + PostgreSQL + Metabase

## Alcance de las 10 actividades

1. **RA2** Investigación de n8n: automatización, nodos, triggers, workflows y arquitectura.
2. **RA2** Investigación de Docker: imágenes, contenedores, volúmenes, redes y Compose.
3. **RA5** Despliegue aislado mediante Compose de n8n, PostgreSQL y Metabase.
4. **RA3** Limpieza genérica: normalización de espacios, estandarización, fechas y validaciones.
5. **RA5** Esquema PostgreSQL con clave primaria compuesta, restricciones, índices y tablas de rechazos.
6. **RA5** Workflow real de n8n con nodos PostgreSQL que ejecuta una carga SQL nativa, normalización y controles de calidad. Se incluye también el ETL Python opcional.
7. **RA5** Conexión de Metabase a PostgreSQL por red interna de Docker.
8. **RA4** Dashboard en Metabase con tarjetas de indicadores, barras, tendencias, tablas y filtros.
9. **RA6** Informe ejecutivo: resultados reales, metodología, capturas, hallazgos y recomendaciones.
10. **RA5** Registro de entregas, seguimiento y evidencia de puntualidad.

## Fuente real

SEPS, Organizaciones EPS 2026:
https://estadisticas.seps.gob.ec/index.php/sdm_downloads/organizaciones-2026/

La fuente descargada en `data/2026-OEPS-MEN.zip` contiene `2026.txt` (TSV, encabezado y 14 campos). No se inventan registros.

## Requisitos y ejecución

Docker Desktop en Windows 11. En PowerShell, dentro de esta carpeta:

```powershell
docker compose up -d
docker compose ps
Invoke-WebRequest http://localhost:15678/healthz -UseBasicParsing
```

No se reutiliza ni modifica el antiguo contenedor `n8n` (puerto 5678).
Accesos de este proyecto:
- n8n: http://localhost:15678
- Metabase: http://localhost:13000
- API ETL Python opcional: http://localhost:18080/health (activar con `docker compose --profile python-etl up -d --build`)
- PostgreSQL local: localhost:55432

La contraseña de Postgres, los datos de la base interna Metabase y la clave de cifrado de n8n se guardan en `.env`, que está excluido de git. No publicar este archivo. En un volumen PostgreSQL nuevo, `sql/00_metabase_app_db.sh` crea automáticamente la base `metabase_app` y su rol.

## Importación

Se creó un administrador local de n8n y se importaron el workflow `SEPS 2026 - ETL PostgreSQL y controles` (`n8n/workflow-seps-sql.json`) y la credencial `SEPS PostgreSQL`. Las credenciales locales del administrador están en `.env`, en las variables `SEPS_OWNER_EMAIL` y `SEPS_OWNER_PASSWORD`. En un entorno nuevo, reproducir la configuración con `powershell -ExecutionPolicy Bypass -File .\scripts\configurar-n8n.ps1`; el script borra el JSON temporal con la contraseña de PostgreSQL tras importar la credencial.

El workflow principal llama `SELECT * FROM seps.cargar_organizaciones()` mediante un nodo PostgreSQL y después consulta `seps.v_indicadores`. PostgreSQL usa el archivo oficial `/seps-data/2026.txt` montado en solo lectura, y ejecuta `COPY`, validación de tipos, transformación y UPSERT; n8n orquesta y verifica los indicadores resultantes.

**Prueba efectuada:** el workflow se ejecutó mediante `docker compose run --rm n8n execute --id=SEPS2026ETL00001` y terminó con `status: success`.

Para comprobar la función SQL de carga:
```powershell
docker compose exec -T postgres psql -U seps -d seps -c "SELECT * FROM seps.cargar_organizaciones();"
```

El flujo alternativo `n8n/workflow-seps.json` llama `POST http://etl:8080/run` y requiere activar el servicio opcional Python con el perfil `python-etl`. No es el flujo principal verificado.

La importación es idempotente por `(fecha_corte, ruc)` gracias a `ON CONFLICT DO UPDATE`. Un segundo recorrido no debe incrementar el número de claves únicas para los mismos registros. La tabla `seps.rechazos` registra filas inválidas para auditoría.

## Metabase

**Configuración ejecutada y verificada:** Metabase ya está disponible en `http://localhost:13000/dashboard/2`. El script siguiente permite reproducir el aprovisionamiento en un entorno nuevo:

```powershell
docker compose up -d metabase
powershell -ExecutionPolicy Bypass -File .\scripts\configurar-metabase.ps1
```

El script configura administrador, fuente PostgreSQL, siete preguntas (tarjetas, líneas, barras, sectores y tabla), dashboard **Panorama SEPS 2026** y filtros de provincia y sector. Las variables `METABASE_ADMIN_EMAIL` y `METABASE_ADMIN_PASSWORD` quedan guardadas en `.env`. Guardar evidencia de la conexión, preguntas y dashboard.

La consulta de siete tarjetas fue comprobada por API, con resultados nacionales consistentes. También se probó una consulta parametrizada de `CHIMBORAZO` mediante la API de dataset, devolviendo 769 organizaciones para agosto de 2026. Los parámetros del dashboard están enlazados a las siete tarjetas.

## Consultas para evidencias

```sql
SELECT * FROM seps.v_indicadores ORDER BY fecha_corte;
SELECT provincia, SUM(organizaciones) organizaciones FROM seps.v_resumen_provincias
 GROUP BY provincia ORDER BY organizaciones DESC;
SELECT estado, SUM(registros_leidos) leidos, SUM(registros_rechazados) rechazados
 FROM seps.importaciones GROUP BY estado;
SELECT COUNT(*) AS filas, COUNT(DISTINCT (fecha_corte, ruc)) AS claves_unicas
 FROM seps.organizaciones;
```

## Evidencias para actividades 9 y 10

El informe ejecutivo debe incluir portada, objetivos, tecnologías, capturas de `docker compose ps`, esquema PostgreSQL, ejecución de n8n, métricas reales, consulta de Metabase, dashboard, conclusiones y bibliografía. Registrar fechas planificadas/reales y recepción de documentos en una hoja de seguimiento. No afirmar entregas realizadas sin comprobantes.
