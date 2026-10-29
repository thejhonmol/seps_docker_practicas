# Provisionamiento local automatizado de Metabase SEPS 2026.
# Ejecutar desde PowerShell 5.1 cuando docker compose ps muestre Metabase en ejecución.
$ErrorActionPreference = 'Stop'
$base = 'http://localhost:13000'
$root = Split-Path -Parent $PSScriptRoot
$envPath = Join-Path $root '.env'
if (-not (Test-Path -LiteralPath $envPath)) { throw '.env no existe' }
$secrets = @{}
Get-Content -LiteralPath $envPath | ForEach-Object {
  if ($_ -match '^([A-Z_]+)=(.*)$') { $secrets[$matches[1]] = $matches[2] }
}

function MbRequest {
  param([string] $Method='GET', [string] $Path, $Data=$null)
  $parameters = @{Uri = "$base$Path"; Method = $Method; TimeoutSec = 60}
  if ($script:session) { $parameters.Headers = @{'X-Metabase-Session' = $script:session} }
  if ($null -ne $Data) {
    $parameters.ContentType = 'application/json; charset=utf-8'
    $parameters.Body = ConvertTo-Json -InputObject $Data -Depth 25 -Compress
  }
  return Invoke-RestMethod @parameters
}
try { $health = MbRequest -Path '/api/health' } catch {
  throw "Metabase no está disponible en $base. Comprueba docker compose ps y sus logs."
}
if ($health.status -ne 'ok') { throw 'Metabase no está listo' }

if (-not $secrets.ContainsKey('METABASE_ADMIN_EMAIL')) {
  Add-Content -LiteralPath $envPath 'METABASE_ADMIN_EMAIL=seps-bi@example.com'
  $secrets['METABASE_ADMIN_EMAIL'] = 'seps-bi@example.com'
}
if (-not $secrets.ContainsKey('METABASE_ADMIN_PASSWORD')) {
  $buf = New-Object byte[] 32
  [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($buf)
  $pwd = ([Convert]::ToBase64String($buf)).Replace('+','A').Replace('/','B').Replace('=','')
  Add-Content -LiteralPath $envPath ('METABASE_ADMIN_PASSWORD=' + $pwd)
  $secrets['METABASE_ADMIN_PASSWORD'] = $pwd
}

$properties = MbRequest -Path '/api/session/properties'
if ($properties.'has-user-setup') {
  $loggedIn = MbRequest -Method 'POST' -Path '/api/session' -Data @{
    username = $secrets['METABASE_ADMIN_EMAIL']
    password = $secrets['METABASE_ADMIN_PASSWORD']
  }
  $script:session = $loggedIn.id
  Write-Output 'Metabase: inicio de sesión correcto'
} else {
  $setup = MbRequest -Method 'POST' -Path '/api/setup' -Data @{
    token = $properties.'setup-token'
    user = @{
      email = $secrets['METABASE_ADMIN_EMAIL']
      first_name = 'Administrador'
      last_name = 'SEPS'
      password = $secrets['METABASE_ADMIN_PASSWORD']
    }
    prefs = @{site_name='SEPS - Prácticas Preprofesionales';site_locale='es'}
  }
  $script:session = $setup.id
  Write-Output 'Metabase: administrador local creado'
}

$dbList = MbRequest -Path '/api/database'
$db = @($dbList.data) | Where-Object name -eq 'SEPS - Datos Estadísticos' | Select-Object -First 1
if (-not $db) {
  $db = MbRequest -Method 'POST' -Path '/api/database' -Data @{
    name = 'SEPS - Datos Estadísticos'
    engine = 'postgres'
    details = @{
      host = 'postgres'
      port = 5432
      dbname = $secrets['POSTGRES_DB']
      user = $secrets['POSTGRES_USER']
      password = $secrets['POSTGRES_PASSWORD']
      ssl = $false
    }
  }
}
if (-not $db.id) { throw 'No se pudo configurar la conexión a PostgreSQL.' }
Write-Output ('Metabase: conexión PostgreSQL ID ' + $db.id)

$collectionName = 'Prácticas SEPS 2026'
$collections = @(MbRequest -Path '/api/collection')
$collection = $collections | Where-Object name -eq $collectionName | Select-Object -First 1
if (-not $collection) {
  $collection = MbRequest -Method 'POST' -Path '/api/collection' -Data @{name=$collectionName;color='#509EE2'}
}

$tags = @{
  provincia = @{name='provincia';'display-name'='Provincia';type='text'}
  sector = @{name='sector';'display-name'='Sector';type='text'}
}
$q = @(
  @{name='SEPS - Total último corte';display='scalar';sql='SELECT COUNT(*) AS total FROM seps.organizaciones WHERE fecha_corte = (SELECT MAX(fecha_corte) FROM seps.organizaciones) [[ AND provincia = {{provincia}} ]] [[ AND sector = {{sector}} ]]';pos=@(0,0,8,4)}
  @{name='SEPS - Activas último corte';display='scalar';sql="SELECT COUNT(*) AS activas FROM seps.organizaciones WHERE fecha_corte = (SELECT MAX(fecha_corte) FROM seps.organizaciones) AND estado_juridico = 'ACTIVA' [[ AND provincia = {{provincia}} ]] [[ AND sector = {{sector}} ]]";pos=@(8,0,8,4)}
  @{name='SEPS - Provincias último corte';display='scalar';sql="SELECT COUNT(DISTINCT provincia) AS provincias FROM seps.organizaciones WHERE fecha_corte = (SELECT MAX(fecha_corte) FROM seps.organizaciones) AND provincia NOT IN ('NO DEFINIDO', 'ZONA NO DELIMITADA') [[ AND provincia = {{provincia}} ]] [[ AND sector = {{sector}} ]]";pos=@(16,0,8,4)}
  @{name='SEPS - Evolución mensual';display='line';sql='SELECT fecha_corte AS mes, COUNT(*) AS organizaciones FROM seps.organizaciones WHERE 1=1 [[ AND provincia = {{provincia}} ]] [[ AND sector = {{sector}} ]] GROUP BY fecha_corte ORDER BY fecha_corte';pos=@(0,4,24,8)}
  @{name='SEPS - Por provincia';display='bar';sql='SELECT provincia,COUNT(*) AS organizaciones FROM seps.organizaciones WHERE fecha_corte=(SELECT MAX(fecha_corte) FROM seps.organizaciones) [[ AND provincia = {{provincia}} ]] [[ AND sector = {{sector}} ]] GROUP BY provincia ORDER BY organizaciones DESC';pos=@(0,12,12,9)}
  @{name='SEPS - Por sector';display='pie';sql='SELECT sector,COUNT(*) AS organizaciones FROM seps.organizaciones WHERE fecha_corte=(SELECT MAX(fecha_corte) FROM seps.organizaciones) [[ AND provincia = {{provincia}} ]] [[ AND sector = {{sector}} ]] GROUP BY sector ORDER BY organizaciones DESC';pos=@(12,12,12,9)}
  @{name='SEPS - Detalle provincial';display='table';sql='SELECT provincia,sector,estado_juridico,COUNT(*) AS organizaciones FROM seps.organizaciones WHERE fecha_corte=(SELECT MAX(fecha_corte) FROM seps.organizaciones) [[ AND provincia = {{provincia}} ]] [[ AND sector = {{sector}} ]] GROUP BY provincia,sector,estado_juridico ORDER BY organizaciones DESC LIMIT 50';pos=@(0,21,24,9)}
)
$cards = @()
$existingCards = @(MbRequest -Path '/api/card?f=all')
foreach($item in $q) {
  $found = $existingCards | Where-Object name -eq $item.name | Select-Object -First 1
  if (-not $found) {
    $found = MbRequest -Method 'POST' -Path '/api/card' -Data @{
      name = $item.name
      type = 'question'
      display = $item.display
      collection_id = $collection.id
      visualization_settings = @{}
      dataset_query = @{
        database = [int]$db.id
        type = 'native'
        native = @{query=$item.sql; 'template-tags'=$tags}
      }
    }
  }
  if (-not $found.id) {throw ('Error creando pregunta ' + $item.name)}
  $cards += @{id=$found.id; pos=$item.pos; name=$item.name}
  Write-Output ('Pregunta: ' + $item.name + ' #' + $found.id)
}
$dashList = @(MbRequest -Path '/api/dashboard?f=all')
$dash = $dashList | Where-Object name -eq 'Panorama SEPS 2026' | Select-Object -First 1
if (-not $dash) {
  $dash = MbRequest -Method 'POST' -Path '/api/dashboard' -Data @{
    name = 'Panorama SEPS 2026'
    description = 'Análisis oficial de Organizaciones EPS, cortes enero-agosto 2026'
    collection_id = $collection.id
  }
}
$dashcards = @()
$i = 1
foreach($item in $cards) {
  $dashcards += @{
    id = -$i
    card_id = [int]$item.id
    row = $item.pos[1]
    col = $item.pos[0]
    size_x = $item.pos[2]
    size_y = $item.pos[3]
    parameter_mappings = @(
      @{parameter_id='seps_provincia';card_id=[int]$item.id;target=@('variable',@('template-tag','provincia'))},
      @{parameter_id='seps_sector';card_id=[int]$item.id;target=@('variable',@('template-tag','sector'))}
    )
  }
  $i += 1
}
$updated = MbRequest -Method 'PUT' -Path ('/api/dashboard/' + $dash.id) -Data @{
  parameters = @(
    @{id='seps_provincia';name='Provincia';slug='provincia';type='string/='},
    @{id='seps_sector';name='Sector';slug='sector';type='string/='}
  )
  dashcards = $dashcards
}
Write-Output ('Dashboard creado: ' + $base + '/dashboard/' + $dash.id)
Write-Output ('Gráficos: ' + $cards.Count)
Write-Output 'Credenciales de administrador: consultar METABASE_ADMIN_EMAIL y METABASE_ADMIN_PASSWORD en .env'
