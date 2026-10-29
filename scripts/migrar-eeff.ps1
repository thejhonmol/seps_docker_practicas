# Crear el esquema financiero en volúmenes existentes, sin borrar datos.
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path -Parent $PSScriptRoot)
$schema = Get-Content -Raw -Encoding UTF8 sql/01_schema.sql
$schema | docker compose exec -T postgres sh -c 'psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"'
if ($LASTEXITCODE -ne 0) { throw 'Falló la migración financiera' }
Write-Output 'Esquema seps_fin preparado. Los datos anteriores permanecen separados.'
