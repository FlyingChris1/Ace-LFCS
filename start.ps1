$ErrorActionPreference='Stop'
Set-Location $PSScriptRoot
$mp='C:\Program Files\Multipass\bin\multipass.exe'
if (-not (Test-Path -LiteralPath $mp)) { throw 'Install Multipass first.' }
if (-not (Get-Command node -ErrorAction SilentlyContinue)) { throw 'Node.js is required.' }
node .\server.js
