# Avance del informe ejecutivo de prácticas preprofesionales

**Entrega:** Medio ciclo  
**Tema:** Automatización del procesamiento y visualización de boletines financieros de la SEPS mediante Docker, n8n, PostgreSQL y Metabase  
**Estudiante:** Molina Paredes Jhonny Fabricio  
**Institución:** Escuela Superior Politécnica de Chimborazo  
**Facultad:** Informática y Electrónica  
**Carrera:** Software  
**Sede:** Matriz Riobamba  
**Período académico:** Septiembre 2026 – Febrero 2027  
**Tutor académico:** Ing. Sonia Patricia Cordovez Machado  
**Tutor externo:** Ing. Myriam Johanna Naranjo Vaca  
**Proyecto:** Desarrollo de herramientas de Business Intelligence y data analytics para fortalecer el ecosistema empresarial MIPYMES: caso Riobamba y Ambato  
**Lugar y fecha:** Riobamba, 29 de octubre de 2026

## Índice

1. Resumen
2. Objetivos
3. Generalidades
4. Desarrollo de las prácticas
5. Conclusiones preliminares
6. Recomendaciones
7. Evidencias y fuentes

## 1 Resumen

Este avance documenta la adaptación de la solución a seis boletines financieros del archivo `2026-EEFF-MEN.zip`. Se preparó un lector de Excel que transforma cuentas e indicadores a registros por fecha, grupo y entidad, conservando la referencia al archivo, hoja y celda. La lectura local identificó 281.950 celdas: 263.703 numéricas, 18.238 sin dato y 9 errores de Excel. Se prepararon el esquema PostgreSQL, el flujo de n8n y el aprovisionamiento del dashboard. Su ejecución integrada en Docker y las capturas quedan pendientes; los resultados de la fuente anterior no se presentan como pruebas de esta versión.

## 2 Objetivos

**Objetivo general:** implementar una solución para procesar y visualizar información financiera publicada en los boletines de la SEPS, mediante herramientas de automatización, almacenamiento y Business Intelligence.

**Objetivos específicos:**

- Configurar un entorno con Docker, n8n, PostgreSQL y Metabase.
- Extraer y normalizar los estados e indicadores financieros conservando sus períodos, unidades y procedencia.
- Registrar valores faltantes y errores del origen, y controlar la unicidad de los datos importados.
- Preparar visualizaciones por entidad, grupo y período que eviten duplicar saldos y agregar tasas incorrectamente.
- Documentar los avances y las evidencias de medio ciclo.

## 3 Generalidades

Las prácticas se enmarcan en el proyecto MIPYMES de la Escuela Superior Politécnica de Chimborazo consignado en el Anexo B. El trabajo técnico de este avance consiste en preparar herramientas de tratamiento y visualización de información financiera pública. La SEPS es la fuente de los boletines, no la institución receptora de las prácticas.

El área, departamento y funciones específicas asignadas deben completarse con la información confirmada por los tutores. La relación de los análisis financieros con los objetivos del proyecto MIPYMES debe explicarse conforme a esa asignación; no se atribuyen a los boletines datos empresariales que no contienen.

## 4 Desarrollo de las prácticas

### Fuente y cobertura

Se examinaron seis archivos XLSM: CONAFIPS, FINANCOOP, Mutualistas y Segmentos 1, 2 y 3. Se importan las hojas de estados financieros y de indicadores financieros. Los dos primeros boletines incluyen enero a septiembre; los otros cuatro contienen septiembre de 2026 en las hojas seleccionadas. Las hojas auxiliares, rankings, clasificación de cartera y resultados del ejercicio se mantienen fuera del alcance de esta importación inicial.

La fuente se identifica mediante SHA256 `bbf11db7bfc043ad852e770a7eba013e84e5bf210c630a24f31572651628dc0b`. Los XLSM se leen sin ejecutar macros ni recalcular fórmulas.

### Productos preparados

- Lector y auditoría de los seis boletines con trazabilidad por celda.
- Esquema `seps_fin` con valores, importaciones, observaciones y vistas analíticas.
- Carga transaccional que conserva la base anterior ante fallos estructurales y reemplaza únicamente los grupos y períodos de la nueva fuente.
- Workflow n8n que solicita la importación al servicio ETL y muestra sus resultados.
- Script de Metabase con siete preguntas y filtros por grupo, entidad y período.
- Actividades resumidas del Anexo B y registro de entregas pendiente de constancias.

La matriz detallada de actividades y resultados de aprendizaje se conserva en `ANEXO_B_ACTIVIDADES.md`.

### Resultados verificados de la lectura local

| Grupo | Entidades sin columna total | Períodos disponibles |
|---|---:|---|
| CONAFIPS | 1 | Enero–septiembre de 2026 |
| FINANCOOP | 1 | Enero–septiembre de 2026 |
| Mutualistas | 4 | Septiembre de 2026 |
| Segmento 1 | 44 | Septiembre de 2026 |
| Segmento 2 | 66 | Septiembre de 2026 |
| Segmento 3 | 91 | Septiembre de 2026 |

Se identificaron 270.164 celdas de cuentas y 11.786 celdas de indicadores. Las 207 entidades se cuentan por nombre dentro de su grupo; no se realizó una conciliación de identidad mediante RUC. Los vacíos y errores se preservan como nulos con su estado, sin sustituirlos por cero. Las sumas de activos de las entidades concilian con los totales de Mutualistas y Segmentos 1–3 con diferencias menores a un centavo.

Seis pruebas unitarias y una prueba adicional con el ZIP real comprobaron la lectura de fechas, totales, cuentas, porcentajes, vacíos, errores y rechazo de claves duplicadas. La auditoría está en `auditoria_fuente.json`. No se afirma todavía una carga exitosa en PostgreSQL, una ejecución de n8n ni un dashboard visualmente validado para esta fuente.

### Criterios de análisis

Los totales publicados se separan de las entidades. Para activos, pasivos y patrimonio se usan exclusivamente las cuentas 1, 2 y 3, evitando sumar cuentas padre e hijas. Se selecciona un corte por consulta; los saldos mensuales no se acumulan. Las tasas se presentan por entidad y no se suman ni promedian entre instituciones. Las sumas de saldos entre grupos no equivalen a estados financieros consolidados.

## 5 Conclusiones preliminares

La estructura heterogénea de los boletines requiere un proceso de lectura diferente al usado para el conjunto anterior. El lector preparado conserva las diferencias de fechas y encabezados y permite identificar errores de origen. La conciliación de activos aporta una comprobación independiente de la extracción. La validación del objetivo de integración queda pendiente de ejecutar los servicios y guardar sus evidencias.

## 6 Recomendaciones

Ejecutar la carga con la fuente auditada, repetirla para comprobar idempotencia y revisar las observaciones. Validar el workflow y las siete preguntas de Metabase. Completar las capturas, el área de prácticas, las fechas efectivas y las firmas correspondientes. Conservar las unidades y períodos originales al interpretar los indicadores y documentar cualquier ampliación del alcance.

## 7 Evidencias y fuentes

Fuente primaria: archivo `2026-EEFF-MEN.zip` proporcionado para las prácticas, boletines financieros de septiembre de 2026. Evidencias técnicas incluidas: auditoría JSON, código del parser y pruebas unitarias. Evidencias pendientes: servicios Docker activos, carga y repetición en PostgreSQL, ejecución n8n, conexión y dashboard de Metabase, y constancias de entrega.

El avance se organiza conforme al Anexo E de la guía académica adjunta. Al trasladarlo al documento institucional se debe respetar su formato y límite de páginas. El código y este borrador no sustituyen la evaluación ni las firmas del estudiante y los tutores.

**Firma del estudiante:** pendiente
