param([Parameter(Mandatory=$true)][string]$ArchivoZip)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$source = (Resolve-Path -LiteralPath $ArchivoZip).Path
$target = Join-Path $root 'data/2026-EEFF-MEN.zip'
$expected = 'bbf11db7bfc043ad852e770a7eba013e84e5bf210c630a24f31572651628dc0b'
$hash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
if ($hash -ne $expected) { throw 'El ZIP no coincide con la fuente auditada de septiembre de 2026.' }
if ($source -ne $target) { Copy-Item -LiteralPath $source -Destination $target -Force }
Write-Output 'Fuente financiera verificada y preparada. No requiere descomprimir ni habilitar macros.'
