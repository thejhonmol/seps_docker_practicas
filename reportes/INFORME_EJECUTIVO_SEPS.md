# Informe ejecutivo de prácticas preprofesionales

**Tema:** Implementación de una solución de automatización y visualización de datos estadísticos de la SEPS con n8n, PostgreSQL, Metabase y Docker.

**Institución:** [Completar]  
**Estudiante:** [Completar]  
**Tutor:** [Completar]  
**Periodo:** [Completar]  
**Fecha de elaboración:** 27 de octubre de 2026

## 1. Resumen ejecutivo

Se preparó una arquitectura contenerizada para extraer, normalizar y analizar datos públicos de organizaciones de la Economía Popular y Solidaria (EPS) publicados por la Superintendencia de Economía Popular y Solidaria (SEPS) de Ecuador. Se trabajó con el archivo oficial **ORGANIZACIONES-2026**, descarga `2026-OEPS-MEN.zip`, que incluye información de ocho cortes mensuales de enero a agosto de 2026.

Se verificaron **164.284 filas de origen**, con 14 campos por registro. PostgreSQL recibió los **164.284 registros**, sin rechazos de formato básico. La clave primaria compuesta `(fecha_corte, ruc)` asegura unicidad por período y organización. Se repitió la importación y se confirmó que el número de registros no aumentó. El workflow de n8n fue importado, ejecutado mediante la CLI y finalizó con **estado success**. **Metabase se instaló correctamente**, se conectó a PostgreSQL, y el dashboard `Panorama SEPS 2026` quedó creado con siete preguntas analíticas y dos parámetros interactivos.

## 2. Objetivo general

Implementar una solución reproducible con Docker que orqueste la carga y análisis de datos estadísticos oficiales de la SEPS en n8n, PostgreSQL y Metabase.

## 3. Metodología

La arquitectura usa Docker Compose, volúmenes persistentes y una red privada del proyecto. PostgreSQL recibe un fichero tabulado (TSV) montado en solo lectura desde el host. Una función de PostgreSQL realiza `COPY` a tabla de preparación, valida campos, estandariza texto y fecha, registra inconsistencias y ejecuta un `UPSERT` hacia la tabla definitiva. n8n activa la función mediante un nodo PostgreSQL y comprueba las vistas agregadas. Metabase consulta los datos de `seps` mediante la red privada; sus propias tablas de configuración se guardan en una **segunda base PostgreSQL `metabase_app`**, con usuario independiente.

**Trazabilidad de datos:** la base publicada por SEPS se utiliza sin agregar registros sintéticos. Para reflejar evolución en el tiempo se conserva el conjunto de observaciones de cada fecha de corte; **la suma de los ocho cortes no representa el total de organizaciones diferentes existentes en agosto**.

## 4. Actividades desarrolladas

| N.º | Actividad | RA | Evidencia y resultado |
|---:|---|---|---|
| 1 | Estudio de n8n | RA2 | Flujo de control, nodo activador y dos nodos PostgreSQL; documentación oficial. |
| 2 | Estudio de Docker | RA2 | Docker Compose, servicios aislados, red de proyecto y volúmenes persistentes. |
| 3 | Entorno Docker | RA5 | PostgreSQL, n8n y Metabase activos en la misma red Docker. |
| 4 | Normalización | RA3 | Estandarización, tipos de datos, calidad de RUC y registros rechazados. |
| 5 | Modelo de datos | RA5 | Esquema `seps`, tres tablas de control, índices y vistas analíticas. |
| 6 | Flujo ETL n8n | RA5 | `SEPS 2026 - ETL PostgreSQL y controles`: ejecución real exitosa. |
| 7 | Conexión a Metabase | RA5 | Conexión a PostgreSQL registrada y consultas API ejecutadas. |
| 8 | Dashboard | RA4 | Siete preguntas ejecutadas correctamente, dashboard disponible y filtros vinculados. |
| 9 | Informe ejecutivo | RA6 | Este documento, que debe complementarse con las capturas finales. |
| 10 | Responsabilidad/puntualidad | RA5 | Matriz de seguimiento `registro_entregas.csv`; completar según constancias reales de entrega. |

## 5. Resultados cuantitativos

| Fecha de corte | Organizaciones | Estado activo |
|---|---:|---:|
| 31 enero 2026 | 20.422 | 17.364 |
| 28 febrero 2026 | 20.448 | 17.382 |
| 31 marzo 2026 | 20.479 | 17.407 |
| 30 abril 2026 | 20.519 | 17.439 |
| 31 mayo 2026 | 20.550 | 17.465 |
| 30 junio 2026 | 20.583 | 17.488 |
| 31 julio 2026 | 20.625 | 17.523 |
| 31 agosto 2026 | **20.658** | **17.556** |

### Último corte disponible: 31 de agosto de 2026

* Total de organizaciones: **20.658**.
* Organizaciones con estado jurídico ACTIVA: **17.556**.
* Sector asociativo: **17.114**; sector cooperativo: **3.375**; sector comunitario: **169**.
* Cobertura geográfica: **24 provincias** y **2 valores geográficos adicionales** en el campo provincia: `NO DEFINIDO` (1 registro) y `ZONA NO DELIMITADA` (10 registros).
* En ocho cortes: **164.284 registros** y **0 duplicados** en la clave `(fecha_corte, ruc)`.
* Segunda carga: cantidad de registros únicos inalterada (**164.284**).

**Hallazgo de calidad:** el atributo `provincia` tiene 26 etiquetas distintas; interpretarlas como 26 provincias sería incorrecto. Se ajustó el KPI para excluir del conteo provincial las dos categorías especiales, aunque estas se conservan en los datos para no alterar el total de organizaciones.

## 6. Arquitectura y controles

```text
SEPS (archivo oficial 2026-OEPS-MEN.zip)
             |
             v
  Docker / PostgreSQL (COPY a origen crudo)
             |
   Limpieza / validación / UPSERT
             |
   Tabla seps.organizaciones
             |
   +---- n8n: orquestación y control
   |
   +---- Metabase: BI, preguntas y dashboard (validación pendiente)
```

Se implementaron controles de RUC de 13 dígitos, razón social no vacía, conversión de fechas y cantidades, unicidad por fecha y RUC, auditoría de importaciones y tabla para rechazos. Este conjunto es **validación estructural básica**; no equivale a validar formalmente todos los dígitos verificadores del RUC ni la situación legal de una entidad.

## 7. Conclusiones

La automatización comprobada permite cargar y actualizar una serie temporal de datos públicos sin duplicar registros, manteniendo trazabilidad de importaciones. PostgreSQL ejecuta la transformación masiva, n8n centraliza la ejecución y verificación, y Metabase presenta los resultados en un dashboard. Se probaron siete preguntas de Metabase, con resultados congruentes con PostgreSQL. La consulta SQL parametrizada para `CHIMBORAZO` devuelve **769 organizaciones** en el corte de agosto; la configuración del dashboard contiene dos filtros enlazados a sus siete preguntas.

## 8. Recomendaciones

Conservar una copia fechada de cada fuente pública y de los archivos de ejecución; evitar interpretar registros acumulados de varios períodos como un stock único de organizaciones; documentar las categorías geográficas especiales; ampliar la validación del dígito verificador del RUC si el alcance académico lo exige; respaldar los volúmenes de Docker y cambiar las contraseñas de cuentas temporales antes de exponer la solución a una red externa.

## 9. Evidencias que deben adjuntarse

Adjuntar capturas verificables de: salida de `docker compose ps`; tablas y consultas de PostgreSQL; ejecución exitosa de n8n (sin mostrar tokens ni claves); datos originales de SEPS; conexión de Metabase a PostgreSQL; siete preguntas y dashboard. **Todavía faltan capturas y documentos firmados o comprobantes de entrega** para cerrar formalmente las actividades 9 y 10.

## 10. Fuentes y bibliografía

* SEPS. Portal estadístico: https://estadisticas.seps.gob.ec/index.php/sdm_downloads/organizaciones-2026/
* n8n. Documentación oficial: https://docs.n8n.io/
* Docker. Docker Compose: https://docs.docker.com/compose/
* PostgreSQL. Comando COPY: https://www.postgresql.org/docs/current/sql-copy.html
* Metabase. Documentación: https://www.metabase.com/docs/latest/

**Nota de integridad académica:** no se incluye como completada ninguna captura, aprobación, conexión BI o entrega documental que no haya sido observada.
