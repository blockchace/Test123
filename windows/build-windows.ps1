param([ValidateSet("win-x64", "win-arm64")][string]$Runtime = "win-x64", [switch]$SkipInstaller)
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot
dotnet test ChaceRecordings.Tests/ChaceRecordings.Tests.csproj --configuration Release
if ($LASTEXITCODE -ne 0) { throw "Fallaron las pruebas" }
dotnet publish ChaceRecordings/ChaceRecordings.csproj --configuration Release --runtime $Runtime --self-contained true -p:PublishSingleFile=false -o "../dist/windows/$Runtime"
if ($LASTEXITCODE -ne 0) { throw "Falló la compilación" }
Compress-Archive -Path "../dist/windows/$Runtime/*" -DestinationPath "../dist/ChaceRecordings-Windows11-$Runtime.zip" -Force
if (!$SkipInstaller) {
    if ($Runtime -ne "win-x64") { throw "El instalador actual es x64; para ARM64 usa -SkipInstaller y la carpeta portátil." }
    $compiler = Get-Command ISCC.exe -ErrorAction SilentlyContinue
    $iscc = if ($compiler) { $compiler.Source } else { "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe" }
    if (!(Test-Path $iscc)) { throw "Instala Inno Setup 6 para generar el instalador, o usa -SkipInstaller." }
    & $iscc installer.iss
    if ($LASTEXITCODE -ne 0) { throw "Falló la creación del instalador" }
}
Write-Host "Archivos generados en dist. No necesitas instalar .NET en el PC de destino."
