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

$collectionName = 'Prácticas SEPS EEFF 2026'
$collections = @(MbRequest -Path '/api/collection')
$collection = $collections | Where-Object name -eq $collectionName | Select-Object -First 1
if (-not $collection) {
  $collection = MbRequest -Method 'POST' -Path '/api/collection' -Data @{name=$collectionName;color='#509EE2'}
}

$tags = @{
  segmento = @{name='segmento';'display-name'='Grupo o segmento';type='text'}
  entidad = @{name='entidad';'display-name'='Entidad';type='text'}
  periodo = @{name='periodo';'display-name'='Período AAAA-MM-DD';type='text'}
}
# Default: latest cut. Dates never sum together. Group totals are excluded in SQL views.
$filter = " WHERE fecha_corte = COALESCE([[ CAST({{periodo}} AS date), ]] (SELECT MAX(fecha_corte) FROM seps_fin.valores)) [[ AND segmento = {{segmento}} ]] [[ AND entidad = {{entidad}} ]]"
$q = @(
  @{name='EEFF - Entidades del corte';display='scalar';sql=('SELECT COUNT(*) AS entidades FROM seps_fin.v_balance' + $filter);pos=@(0,0,6,4)}
  @{name='EEFF - Activos USD del corte';display='scalar';sql=('SELECT CASE WHEN COUNT(activos)=COUNT(*) THEN SUM(activos) END AS activos_usd FROM seps_fin.v_balance' + $filter);pos=@(6,0,6,4)}
  @{name='EEFF - Pasivos USD del corte';display='scalar';sql=('SELECT CASE WHEN COUNT(pasivos)=COUNT(*) THEN SUM(pasivos) END AS pasivos_usd FROM seps_fin.v_balance' + $filter);pos=@(12,0,6,4)}
  @{name='EEFF - Patrimonio USD del corte';display='scalar';sql=('SELECT CASE WHEN COUNT(patrimonio)=COUNT(*) THEN SUM(patrimonio) END AS patrimonio_usd FROM seps_fin.v_balance' + $filter);pos=@(18,0,6,4)}
  @{name='EEFF - Activos por grupo';display='bar';sql=('SELECT segmento,CASE WHEN COUNT(activos)=COUNT(*) THEN SUM(activos) END AS activos_usd FROM seps_fin.v_balance' + $filter + ' GROUP BY segmento ORDER BY activos_usd DESC');pos=@(0,4,12,8)}
  @{name='EEFF - Balance por entidad USD';display='table';sql=('SELECT fecha_corte,segmento,entidad,activos,pasivos,patrimonio,ingresos,gastos FROM seps_fin.v_balance' + $filter + ' ORDER BY segmento,entidad');pos=@(12,4,12,8)}
  @{name='EEFF - Indicadores por entidad';display='table';sql=('SELECT fecha_corte,segmento,entidad,nombre,valor_presentacion,CASE WHEN unidad=''proporcion'' THEN ''%'' ELSE unidad END AS unidad,estado FROM seps_fin.v_indicadores' + $filter + ' ORDER BY segmento,entidad,nombre');pos=@(0,12,24,10)}
)
$cards = @()
$existingCards = @(MbRequest -Path '/api/card?f=all')
foreach($item in $q) {
  $found = $existingCards | Where-Object name -eq $item.name | Select-Object -First 1
  $cardMethod = 'POST'
  $cardPath = '/api/card'
  if ($found) { $cardMethod = 'PUT'; $cardPath = '/api/card/' + $found.id }
  $found = MbRequest -Method $cardMethod -Path $cardPath -Data @{
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
  if (-not $found.id) {throw ('Error creando pregunta ' + $item.name)}
  $cards += @{id=$found.id; pos=$item.pos; name=$item.name}
  Write-Output ('Pregunta: ' + $item.name + ' #' + $found.id)
}
$dashList = @(MbRequest -Path '/api/dashboard?f=all')
$dash = $dashList | Where-Object name -eq 'Panorama financiero SEPS 2026' | Select-Object -First 1
if (-not $dash) {
  $dash = MbRequest -Method 'POST' -Path '/api/dashboard' -Data @{
    name = 'Panorama financiero SEPS 2026'
    description = 'Boletines financieros: corte por defecto septiembre 2026. Filtros exactos por grupo, entidad y período (AAAA-MM-DD). Indicadores en porcentaje, sin sumar tasas. Los totales de varios grupos no constituyen un balance consolidado.'
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
      @{parameter_id='seps_segmento';card_id=[int]$item.id;target=@('variable',@('template-tag','segmento'))},
      @{parameter_id='seps_entidad';card_id=[int]$item.id;target=@('variable',@('template-tag','entidad'))},
      @{parameter_id='seps_periodo';card_id=[int]$item.id;target=@('variable',@('template-tag','periodo'))}
    )
  }
  $i += 1
}
$updated = MbRequest -Method 'PUT' -Path ('/api/dashboard/' + $dash.id) -Data @{
  parameters = @(
    @{id='seps_segmento';name='Grupo o segmento';slug='segmento';type='string/='},
    @{id='seps_entidad';name='Entidad';slug='entidad';type='string/='},
    @{id='seps_periodo';name='Período AAAA-MM-DD';slug='periodo';type='string/='}
  )
  dashcards = $dashcards
}
Write-Output ('Dashboard creado: ' + $base + '/dashboard/' + $dash.id)
Write-Output ('Gráficos: ' + $cards.Count)
Write-Output 'Credenciales de administrador: consultar METABASE_ADMIN_EMAIL y METABASE_ADMIN_PASSWORD en .env'
