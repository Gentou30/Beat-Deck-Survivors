# Run N headless bot games and print results. Usage: ./tools/balance.ps1 -N 6
param([int]$N = 6)
1..$N | ForEach-Object { & $env:GODOT --headless --path "$PSScriptRoot\.." -- --autotest 2>&1 | Select-String "AUTOTEST" }
