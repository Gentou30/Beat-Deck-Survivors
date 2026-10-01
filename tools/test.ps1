# Headless smoke test: bot plays at 5x speed until win/lose. Fails on script errors.
$out = & $env:GODOT --headless --path "$PSScriptRoot\.." -- --autotest 2>&1 | Out-String
Write-Host $out
if ($out -match "SCRIPT ERROR|Parse Error") { exit 1 }
if ($out -notmatch "AUTOTEST result") { exit 1 }
