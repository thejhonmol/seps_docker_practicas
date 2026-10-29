# Fuente financiera

Colocar aquí `2026-EEFF-MEN.zip`, el archivo suministrado por el estudiante, sin descomprimir.
Ejecutar `scripts/preparar-datos.ps1 -ArchivoZip "ruta/al/2026-EEFF-MEN.zip"` para verificar su SHA256 y copiarlo.

SHA256: `bbf11db7bfc043ad852e770a7eba013e84e5bf210c630a24f31572651628dc0b`.

Contiene seis XLSM: CONAFIPS, FINANCOOP, Mutualistas, Segmento 1, Segmento 2 y Segmento 3.
Los archivos binarios se mantienen fuera de Git. La auditoría reproducible está en `reportes/auditoria_fuente.json`.
El ETL lee el ZIP directamente y los valores guardados en las hojas 2 y 5; nunca ejecuta macros.
