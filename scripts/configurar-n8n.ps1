# Configuración reproducible de administrador, credencial PostgreSQL y workflow n8n SEPS.
# Ejecutar una vez que n8n y PostgreSQL estén disponibles.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
$envFile = Join-Path $root '.env'
if (-not (Test-Path $envFile)) { throw 'Falta .env' }
$v = @{}
Get-Content $envFile | ForEach-Object {
  if ($_ -match '^([A-Z_]+)=(.*)$') { $v[$matches[1]] = $matches[2] }
}
if (-not $v.ContainsKey('SEPS_OWNER_EMAIL')) {
  Add-Content $envFile 'SEPS_OWNER_EMAIL=seps-admin@example.com'
  $v['SEPS_OWNER_EMAIL'] = 'seps-admin@example.com'
}
if (-not $v.ContainsKey('SEPS_OWNER_PASSWORD')) {
  $bytes = New-Object byte[] 32
  [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
  $v['SEPS_OWNER_PASSWORD'] = ([Convert]::ToBase64String($bytes)).Replace('+','G').Replace('/','H').Replace('=','')
  Add-Content $envFile ('SEPS_OWNER_PASSWORD=' + $v['SEPS_OWNER_PASSWORD'])
}
$base = 'http://localhost:15678'
try {
  $settings = Invoke-RestMethod -Uri ($base + '/rest/settings') -TimeoutSec 15
} catch {throw 'n8n no responde en el puerto 15678'}
if ($settings.data.userManagement.showSetupOnFirstLoad) {
  $body = @{
    email = $v['SEPS_OWNER_EMAIL']
    firstName = 'Administrador'
    lastName = 'SEPS'
    password = $v['SEPS_OWNER_PASSWORD']
  } | ConvertTo-Json -Compress
  $result = Invoke-RestMethod -Uri ($base + '/rest/owner/setup') -Method Post -Body $body -ContentType 'application/json' -TimeoutSec 20
  if (-not $result.data.id) {throw 'No se pudo configurar el administrador de n8n'}
  Write-Output 'Administrador local n8n configurado'
}
$projectId = (docker compose exec -T postgres psql -tA -U $v['POSTGRES_USER'] -d $v['POSTGRES_DB'] -c "SELECT id FROM public.project WHERE type='personal' ORDER BY id LIMIT 1").Trim()
if ($LASTEXITCODE -ne 0 -or -not $projectId) { throw 'Proyecto personal de n8n no encontrado' }
$credential = @{
  id = 'seps-pg'
  name = 'SEPS PostgreSQL'
  type = 'postgres'
  data = @{
    host = 'postgres'
    port = 5432
    database = $v['POSTGRES_DB']
    user = $v['POSTGRES_USER']
    password = $v['POSTGRES_PASSWORD']
    ssl = 'disable'
  }
}
$file = Join-Path $root 'n8n/seps-credentials.secret.json'
$json = ConvertTo-Json -InputObject @($credential) -Depth 10 -Compress
[IO.File]::WriteAllText($file, $json, (New-Object Text.UTF8Encoding($false)))
try {
  docker compose exec -T n8n n8n import:credentials --input=/seps-workflows/seps-credentials.secret.json --projectId=$projectId
  if ($LASTEXITCODE -ne 0) {throw 'Error importando la credencial PostgreSQL'}
  docker compose exec -T n8n n8n import:workflow --input=/seps-workflows/workflow-seps-sql.json --projectId=$projectId
  if ($LASTEXITCODE -ne 0) {throw 'Error importando workflow SEPS'}
} finally {
  # Los datos cifrados ya están en la base de n8n; no dejar JSON con claves.
  if (Test-Path -LiteralPath $file) {Remove-Item -LiteralPath $file -Force}
}
Write-Output ('n8n configurado: ' + $base)
Write-Output 'Credenciales del administrador: SEPS_OWNER_EMAIL y SEPS_OWNER_PASSWORD en .env'
