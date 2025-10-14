<#
Run-Split-OnlyTxt.ps1
Sicherer Helfer: kopiert nur die .txt aus einem (absoluten) ConvertedDir in einen temporären only-txt-Ordner
und führt danach euren Splitter zuerst im DryRun und auf Bestätigung dann im RealRun aus.

Benutzung (Beispiel aus repo/scripts):
.\run-split-only-txt.ps1 -ConvertedRoot "E:\Uwe\WennKIaufKItrifft\Gesamtwerk"

Parameter:
- ConvertedRoot : (optional) absoluter Pfad zu dem Ordner, der deine 4 *.txt (und evtl. converted/*) enthält.
                 Wenn nicht angegeben, fragt das Script interaktiv nach dem Pfad.
- RepoRoot      : (optional) Basis-Repo-Ordner; Standard ist ein Verzeichnis über dem scripts-Ordner.
- OnlyTxt       : (optional) Ziel-Ordner für die reinen .txt (Standard: <RepoRoot>\only-txt)
- ContentTest   : (optional) Content-Ausgabe für Testlauf (Standard: <RepoRoot>\test-content)
- Out           : (optional) Logs (Standard: <RepoRoot>\split-logs)
#>

param(
  [string]$ConvertedRoot,
  [string]$RepoRoot = (Resolve-Path "..").ProviderPath,
  [string]$OnlyTxt,
  [string]$ContentTest,
  [string]$Out
)

# Defaults
if (-not $OnlyTxt)     { $OnlyTxt    = Join-Path $RepoRoot "only-txt" }
if (-not $ContentTest) { $ContentTest = Join-Path $RepoRoot "test-content" }
if (-not $Out)         { $Out         = Join-Path $RepoRoot "split-logs" }

# Ask for ConvertedRoot if missing
if ([string]::IsNullOrWhiteSpace($ConvertedRoot)) {
  $ConvertedRoot = Read-Host -Prompt "Full path to ConvertedDir (where your .txt live)"
}

# Resolve and validate
try {
  $ConvertedRoot = (Resolve-Path $ConvertedRoot).ProviderPath
} catch {
  Write-Error "ConvertedDir '$ConvertedRoot' not found. Aborting."
  exit 1
}

# Prepare dirs
New-Item -ItemType Directory -Path $OnlyTxt -Force | Out-Null
New-Item -ItemType Directory -Path $ContentTest -Force | Out-Null
New-Item -ItemType Directory -Path $Out -Force | Out-Null

# Copy only .txt (flat into only-txt; if duplicate names exist, later ones overwrite)
$txtFiles = Get-ChildItem -Path $ConvertedRoot -Recurse -File -Filter "*.txt"
if ($txtFiles.Count -eq 0) {
  Write-Error "Keine .txt Dateien unter '$ConvertedRoot' gefunden. Aborting."
  exit 1
}

Write-Host "Copying $($txtFiles.Count) .txt file(s) from '$ConvertedRoot' -> '$OnlyTxt' ..."
foreach ($f in $txtFiles) {
  Copy-Item -Path $f.FullName -Destination $OnlyTxt -Force
}

Write-Host "Copied. Target folder: $OnlyTxt"
Write-Host "Preparing DryRun of splitter (logs to $Out, content to $ContentTest)."

# DryRun
& "$PSScriptRoot\split-md-into-chapters-safe.ps1" -ConvertedDir $OnlyTxt -ContentDir $ContentTest -OutDir $Out -DryRun

Write-Host "`n--- Latest logs (tail) ---"
Get-ChildItem -Path $Out -Filter "split-*.log" -File | Sort-Object LastWriteTime -Descending | Select-Object -First 5 |
  ForEach-Object {
    Write-Host "=== $($_.Name) ==="
    Get-Content $_.FullName -Tail 80
  }

# Confirm real run
$ans = Read-Host -Prompt "DryRun beendet. Soll der echte Lauf ausgeführt werden und $ContentTest mit Index.md gefüllt werden? (j/n)"
if ($ans -match '^[jJ]') {
  Write-Host "Starting real run..."
  & "$PSScriptRoot\split-md-into-chapters-safe.ps1" -ConvertedDir $OnlyTxt -ContentDir $ContentTest -OutDir $Out
  Write-Host "Real run finished. Prüfe $ContentTest und Logs in $Out."
} else {
  Write-Host "Abgebrochen. Es wurden nur die .txt in '$OnlyTxt' kopiert und ein DryRun ausgeführt."
  Write-Host "Wenn du bereit bist, führe das Script erneut und bestätige mit 'j'."
}