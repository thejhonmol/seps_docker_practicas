$ErrorActionPreference = 'Stop'
Set-Location (Split-Path -Parent $PSScriptRoot)
function Query([string]$Sql) {
  $result = $Sql | docker compose exec -T postgres sh -c 'psql -tA -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB"'
  if ($LASTEXITCODE -ne 0) { throw 'Falló consulta de verificación' }
  return ($result -join "`n").Trim()
}
function Import {
  $r = Invoke-RestMethod -Method Post http://localhost:18080/run -TimeoutSec 600
  if ($r.status -ne 'ok' -or $r.read -ne 281950 -or $r.valid -ne 263703 -or $r.observed -ne 18247) {
    throw 'Los resultados difieren de la fuente auditada; revisar la importación.'
  }
}
Import
$before = Query 'SELECT COUNT(*) FROM seps_fin.valores'
# Fingerprint excludes importation_id: repeating a load must not change data or provenance cells.
$sql = "SELECT md5(string_agg(row(fecha_corte,segmento,entidad,tipo,codigo,valor,estado)::text, '' ORDER BY fecha_corte,segmento,entidad,tipo,codigo)) FROM seps_fin.valores"
$fingerprintBefore = Query $sql
Import
$after = Query 'SELECT COUNT(*) FROM seps_fin.valores'
$fingerprintAfter = Query $sql
if ($before -ne $after -or $fingerprintBefore -ne $fingerprintAfter) { throw 'La repetición modificó el conjunto de datos.' }
Write-Output ('Carga e idempotencia verificadas. Claves: ' + $after)
Write-Output 'Validar por separado la ejecución visual de n8n y las siete preguntas de Metabase.'
