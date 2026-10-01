# Export the Web build to build/web and zip it for hosting (itch.io etc.).
# Requires Web export templates in %APPDATA%\Godot\export_templates\4.7.2.stable
New-Item -ItemType Directory -Force "$PSScriptRoot\..\build\web" | Out-Null
& $env:GODOT --headless --path "$PSScriptRoot\.." --export-release "Web" "build/web/index.html"
if (Test-Path "$PSScriptRoot\..\build\web.zip") { Remove-Item "$PSScriptRoot\..\build\web.zip" }
Compress-Archive -Path "$PSScriptRoot\..\build\web\*" -DestinationPath "$PSScriptRoot\..\build\web.zip"
Write-Host "Done: build/web.zip. Local test: python -m http.server 8060 --directory build/web  ->  http://localhost:8060"
