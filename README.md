# Prácticas de medio ciclo con boletines financieros SEPS

El proyecto importa `2026-EEFF-MEN.zip` y analiza estados e indicadores financieros mediante Docker, n8n, PostgreSQL y Metabase. La fuente de organizaciones EPS utilizada anteriormente queda sustituida en el flujo activo.

## Fuente y alcance

Seis boletines XLSM: CONAFIPS, FINANCOOP, Mutualistas y Segmentos 1, 2 y 3. Se leen **2. ESTADO(S) FINANCIERO(S)** y **5. INDICADORES FINANCIEROS**. Las demás hojas (resultados del ejercicio, clasificación de cartera, rankings, catastro y hojas auxiliares) no se importan en este avance. Las cuentas de ingresos y gastos disponibles en la hoja 2 sí se conservan.

- CONAFIPS y FINANCOOP: enero–septiembre de 2026.
- Mutualistas y Segmentos 1–3: septiembre de 2026 en las hojas importadas.
- Se leen los resultados guardados de Excel; no se habilitan macros ni se recalculan fórmulas.
- Una celda vacía o con error no equivale a cero: se conserva con valor nulo y estado de calidad.
- Las columnas `VT_TOTAL` se almacenan para conciliación, pero se excluyen de las vistas por entidad.
- Los saldos no se suman entre meses ni entre cuentas padre e hijas. El dashboard usa las cuentas 1, 2 y 3 para activos, pasivos y patrimonio.
- Los indicadores porcentuales mantienen la proporción original en la base y se multiplican por 100 solamente para presentarlos. No se suman ni promedian tasas entre entidades.
- La suma de grupos es una suma de saldos publicados, **no un balance consolidado**: puede incluir relaciones financieras entre entidades.
- La entidad se identifica por nombre normalizado dentro del grupo; no se inventan RUC ni equivalencias entre nombres.

## Puesta en marcha en Windows PowerShell

Requisitos: Docker Desktop con Compose y PowerShell 5.1 o posterior. Ejecutar desde la raíz del repositorio.

1. Para un entorno nuevo, copiar `.env.example` a `.env` y reemplazar las tres claves de ejemplo. En un entorno existente, conservar `.env` y especialmente la clave de cifrado de n8n.

```powershell
# Solo si todavía no existe .env:
Copy-Item .env.example .env
notepad .env
```

2. Preparar el ZIP proporcionado, sin descomprimir. El script comprueba el SHA256 del archivo auditado. Los binarios no se incluyen en Git.

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\preparar-datos.ps1 -ArchivoZip "$HOME\Downloads\2026-EEFF-MEN.zip"
```

3. Construir e iniciar los cuatro servicios; ETL ahora es obligatorio, no requiere perfil.

```powershell
docker compose up -d --build
docker compose ps
```

4. Cuando PostgreSQL esté listo, aplicar la migración. Es necesaria en volúmenes existentes porque Docker no vuelve a ejecutar los scripts de inicialización. También puede ejecutarse en instalaciones nuevas.

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\migrar-eeff.ps1
Invoke-RestMethod http://localhost:18080/health
```

La migración crea `seps_fin`; conserva las tablas antiguas `seps`, las cuentas de n8n y los volúmenes. **No ejecutar `docker compose down -v` para migrar.**

5. Configurar n8n y ejecutar el nuevo workflow manual desde su interfaz.

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\configurar-n8n.ps1
```

Abrir http://localhost:15678 y ejecutar **SEPS EEFF 2026 - Boletines financieros** (`SEPS2026EEFF001`). El flujo llama a `http://etl:8080/run`; revisa `status`, cuenta las observaciones y presenta el resumen. Una carga puede tardar varios minutos. El flujo anterior, si existe en tu instalación, no debe utilizarse para esta entrega; no se elimina automáticamente.

Para probar la importación directamente, sin atribuir esa prueba a n8n:

```powershell
Invoke-RestMethod -Method Post http://localhost:18080/run -TimeoutSec 600
```

6. Cuando Metabase esté listo y los datos cargados, crear el nuevo dashboard.

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\configurar-metabase.ps1
```

Abrir la dirección que imprime el script (el ID no es fijo). Se crean o actualizan siete preguntas en **Panorama financiero SEPS 2026**: entidades, activos, pasivos, patrimonio, activos por grupo, balance por entidad e indicadores. Filtros exactos: grupo/segmento, entidad y período `AAAA-MM-DD`. Sin período se usa el último corte; por ejemplo, `2026-09-30`. Antes de septiembre solo existen datos de CONAFIPS y FINANCOOP en esta fuente. El dashboard anterior se conserva separado y no representa los nuevos datos.

Accesos: n8n `localhost:15678`, Metabase `localhost:13000`, ETL `localhost:18080`, PostgreSQL `localhost:55432`. Los puertos están vinculados a la interfaz local.

## Modelo y carga

`seps_fin.valores`: una celda financiera por fecha, grupo, entidad, tipo (cuenta o indicador) y código. Incluye archivo, hoja, celda, unidad, estado e importación de origen. `seps_fin.importaciones` registra la huella SHA256, cantidades, estado y errores. `seps_fin.observaciones` registra los vacíos y errores del origen.

La carga valida la estructura de los seis libros y bloquea importaciones simultáneas. Reemplaza de manera atómica solo los grupos y períodos presentes en el ZIP. La clave primaria evita duplicados; repetir una carga conserva el número de claves. Si falla, se revierte el cambio de datos y queda registrada la importación fallida. Los errores y vacíos del origen se conservan como nulos observados; no hacen fracasar una fuente estructuralmente válida.

## Validación efectuada

Lectura local del ZIP y siete pruebas aprobadas (seis unitarias del parser y una con la fuente real): fechas, totales, cuentas, porcentajes, vacíos, errores y claves duplicadas. La auditoría reproducible está en `reportes/auditoria_fuente.json`:

| Medida | Resultado |
|---|---:|
| Libros | 6 |
| Entidades identificadas dentro de cada grupo, sin totales | 207 |
| Celdas de cuentas | 270.164 |
| Celdas de indicadores | 11.786 |
| Valores numéricos | 263.703 |
| Celdas sin dato | 18.238 |
| Errores de Excel | 9 |

Las sumas de activos por entidad concilian con los totales publicados de Mutualistas y Segmentos 1–3 con diferencia menor a USD 0,01. Estos conteos describen celdas de datos, no organizaciones ni transacciones.

No se ha ejecutado el despliegue Docker de esta versión en el entorno de revisión. Quedan por comprobar la carga PostgreSQL, la repetición idempotente, n8n y los gráficos de Metabase. No se reutilizan como evidencia los resultados de la fuente anterior.

Repetir pruebas y auditoría dentro del contenedor:

```powershell
docker compose exec -T etl python audit_source.py /data/2026-EEFF-MEN.zip
# Pruebas locales, con openpyxl instalado:
$env:SOURCE_ZIP = (Resolve-Path data/2026-EEFF-MEN.zip).Path
python -m unittest discover -s tests -v
# Prueba de carga y repetición (requiere servicios y fuente preparados):
powershell -ExecutionPolicy Bypass -File .\scripts\verificar-eeff.ps1
```

Consultas de control:

```sql
SELECT * FROM seps_fin.v_control ORDER BY fecha_corte,segmento;
SELECT id,estado,registros_leidos,registros_validos,registros_observados,error
FROM seps_fin.importaciones ORDER BY id DESC;
SELECT fecha_corte,segmento,COUNT(*) AS entidades,SUM(activos) AS activos_usd
FROM seps_fin.v_balance GROUP BY fecha_corte,segmento ORDER BY fecha_corte,segmento;
SELECT * FROM seps_fin.observaciones ORDER BY id DESC LIMIT 20;
```

## Entrega de medio ciclo

`reportes/ANEXO_B_ACTIVIDADES.md` contiene las actividades resumidas 1–8 y mantiene las 9–10. `reportes/INFORME_EJECUTIVO_SEPS.md` es el avance académico, con resultados de la lectura local y pendientes de validación. `reportes/registro_entregas.csv` no acredita entregas sin constancias.

Añadir capturas de Docker, n8n, consultas y Metabase después de ejecutarlos, y completar las fechas y firmas reales. El avance del 50 % del informe se presenta conforme a la guía institucional; el repositorio por sí solo no acredita horas ni aprobación del tutor.
