param([string]$Godot = 'C:\Tools\Godot\4.7.1\Godot_v4.7.1-stable_win64.exe')
# Imports any new or changed assets, then starts the game. The desktop shortcut runs this, so a
# launch always reflects the current checkout; an import with nothing to do takes a few seconds.
$ErrorActionPreference = 'Stop'
$project = Split-Path $PSScriptRoot -Parent
$output = Join-Path $project 'previews\launch'
New-Item -ItemType Directory -Force -Path $output | Out-Null
$importLog = Join-Path $output 'import.log'
$import = Start-Process -FilePath $Godot -ArgumentList @('--headless','--path',('"{0}"' -f $project),'--editor','--import','--log-file',('"{0}"' -f $importLog)) -WorkingDirectory $project -WindowStyle Hidden -Wait -PassThru
if ($import.ExitCode -ne 0 -or (Select-String -LiteralPath $importLog -Pattern 'SCRIPT ERROR:|Parse Error:|Error importing' -Quiet)) { throw "The Outpost import failed; see $importLog." }
$runtimeLog = Join-Path $output 'runtime.log'
Start-Process -FilePath $Godot -ArgumentList @('--path',('"{0}"' -f $project),'--log-file',('"{0}"' -f $runtimeLog)) -WorkingDirectory $project -WindowStyle Normal
