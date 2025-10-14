<#
Pandoc → Markdown → run splitter (DryRun first)

Usage (from repo root):
  # Dry run
  pwsh .\scripts\pandoc-html-to-md-and-split.ps1 -HtmlFile 'E:\Uwe\WennKIaufKItrifft\Gesamtwerk\Gedankenstreich_Gesamtwerk.html' -TmpConverted 'E:\Uwe\WennKIaufKItrifft\Gesamtwerk\tmp\converted' -RunSplitter -DryRun

  # Actual run (after inspection)
  pwsh .\scripts\pandoc-html-to-md-and-split.ps1 -HtmlFile 'E:\Uwe\WennKIaufKItrifft\Gesamtwerk\Gedankenstreich_Gesamtwerk.html' -TmpConverted 'E:\Uwe\WennKIaufKItrifft\Gesamtwerk\tmp\converted' -RunSplitter

Params:
  -HtmlFile      Path to the Word-exported HTML file.
  -TmpConverted  Folder where pandoc's Markdown + extracted media are placed.
  -RunSplitter   If provided, call your split script afterwards (DryRun first).
  -DryRun        If present, run the splitter with -DryRun only (no writes).
#>

# Version: v35
param(
  [Parameter(Mandatory = $true)][string]$HtmlFile,
  [Parameter(Mandatory = $true)][string]$TmpConverted,
  [switch]$RunSplitter,
  [switch]$DryRun
)

# -----------------------------------------
# Helpers
# -----------------------------------------
function Ensure-Dir {
  param([string]$path)
  if (-not (Test-Path $path)) {
    New-Item -ItemType Directory -Path $path -Force | Out-Null
  }
}

function Timestamp {
  return (Get-Date).ToString('yyyy-MM-ddTHH-mm-ss')
}

function Read-File-AutoDetect {
  param([string]$Path)

  try {
    $textUtf8 = Get-Content -Raw -Encoding UTF8 -Path $Path -ErrorAction Stop
  } catch {
    $textUtf8 = $null
  }

  if ($null -eq $textUtf8) {
    return Get-Content -Raw -Encoding Default -Path $Path
  }

  if ($textUtf8.Contains([char]0xFFFD)) {
    try {
      $bytes = [System.IO.File]::ReadAllBytes($Path)
      $enc1252 = [System.Text.Encoding]::GetEncoding(1252)
      $text1252 = $enc1252.GetString($bytes)
      if (-not $text1252.Contains([char]0xFFFD)) { return $text1252 }
    } catch {
      # fall through and return UTF8
    }
  }

  return $textUtf8
}

function Make-BandSlug {
  param([string]$filePath)
  $name = [IO.Path]::GetFileNameWithoutExtension($filePath)
  if ($name -match '(?i)band[\s_-]*([ivxIVX]+)') {
    $roman = $matches[1].ToLower()
    $roman = $roman -replace '[^ivx]', ''
    return ('band-{0}' -f $roman)
  }
  $slug = $name -replace '[^A-Za-z0-9]+','-'
  return $slug.ToLower()
}

function Sanitize-For-Slug {
  param([string]$s)
  if (-not $s) { return $s }
  $s = $s -replace '[\\/]+','-'
  $s = $s.Trim() -replace '^\.+|\.+$',''
  return $s
}

function Get-H1-Sections {
  param([string]$htmlText)
  $pattern = '(?si)<h1\b[^>]*>.*?</h1>'
  $matches = [regex]::Matches($htmlText, $pattern)
  $sections = @()
  for ($i = 0; $i -lt $matches.Count; $i++) {
    $m = $matches[$i]
    $start = $m.Index
    $end = if ($i -lt ($matches.Count - 1)) { $matches[$i+1].Index } else { $htmlText.Length }
    $innerText = ($m.Value -replace '(?si)<[^>]+>', ' ') -replace '\s+',' '
    $innerText = $innerText.Trim()
    $sections += @{
      H1 = $m.Value
      Title = $innerText
      Start = $start
      End = $end
    }
  }
  return $sections
}

function Normalize-Title {
  param([string]$s)
  if (-not $s) { return '' }

  try { $d = [System.Net.WebUtility]::HtmlDecode($s) } catch { $d = $s }

  $d = $d -replace '<[^>]+>',' '
  $d = $d -replace "`u00A0"," "
  $d = $d -replace '[\x00-\x1F\x7F\u200B\u200C\u200D\uFEFF]',' '
  $d = $d -replace '\s+',' '
  $d = $d.Trim()

  try {
    $d = $d.Normalize([System.Text.NormalizationForm]::FormC)
  } catch {
    # ignore on runtimes without Normalize overload
  }

  return $d
}

function Clean-For-Match {
  param([string]$s)
  if (-not $s) { return '' }
  $t = Normalize-Title $s
  try { $t = $t.ToLowerInvariant() } catch { $t = $t.ToLower() }
  return $t
}

function Make-Backups {
  param(
    [string]$mdPath,
    [string]$htmlPath
  )
  $bakTs = Timestamp
  $backups = @{}
  if (Test-Path $mdPath) {
    $mdBak = $mdPath + '.' + $bakTs + '.bak'
    Copy-Item -Path $mdPath -Destination $mdBak -Force
    $backups.MD = $mdBak
  }
  if (Test-Path $htmlPath) {
    $htmlBak = $htmlPath + '.' + $bakTs + '.bak'
    Copy-Item -Path $htmlPath -Destination $htmlBak -Force
    $backups.HTML = $htmlBak
  }
  return $backups
}

function Restore-Backups {
  param($backups, [string]$mdPath, [string]$htmlPath)
  if ($backups -and $backups.ContainsKey('MD')) {
    Copy-Item -Path $backups.MD -Destination $mdPath -Force
    Write-Output ('Restored MD from backup: {0}' -f $backups.MD)
  }
  if ($backups -and $backups.ContainsKey('HTML')) {
    Copy-Item -Path $backups.HTML -Destination $htmlPath -Force
    Write-Output ('Restored HTML from backup: {0}' -f $backups.HTML)
  }
}

function Safe-Remove {
  param([string]$path)
  try { Remove-Item -Force $path -ErrorAction SilentlyContinue } catch {}
}

# remove any existing index.md/index.html under targetDir (recursively) with backups
function Remove-Existing-Targets {
  param([string]$targetDir)

  if (-not $targetDir) { return }
  Ensure-Dir -path $targetDir

  $mdFiles = @((Get-ChildItem -Path $targetDir -Filter 'index.md' -Recurse -File -ErrorAction SilentlyContinue))
  $htmlFiles = @((Get-ChildItem -Path $targetDir -Filter 'index.html' -Recurse -File -ErrorAction SilentlyContinue))

  $allFiles = @()
  if ($mdFiles.Count -gt 0) { $allFiles += $mdFiles }
  if ($htmlFiles.Count -gt 0) { $allFiles += $htmlFiles }

  foreach ($f in $allFiles) {
    try {
      attrib -R $f.FullName -ErrorAction SilentlyContinue
      attrib -H $f.FullName -ErrorAction SilentlyContinue
      attrib -S $f.FullName -ErrorAction SilentlyContinue
    } catch {}

    try {
      $bak = $f.FullName + '.' + (Timestamp) + '.bak'
      Copy-Item -Path $f.FullName -Destination $bak -Force -ErrorAction SilentlyContinue
    } catch {}

    try {
      Remove-Item -Force -Path $f.FullName -ErrorAction SilentlyContinue
      Write-Output ("Removed existing file: {0}" -f $f.FullName)
    } catch {
      Write-Warning ("Failed to remove existing file {0}: {1}" -f $f.FullName, $_.Exception.Message)
    }
  }
}

function Build-TargetDir {
  param(
    [string]$contentRoot,
    [string]$bandSlug,
    [string]$chapterSlug
  )

  try {
    $contentRootFull = [System.IO.Path]::GetFullPath($contentRoot)
  } catch {
    $contentRootFull = $contentRoot -replace '[\\/]+','\'
  }

  if ($bandSlug) { $bandSlug = Sanitize-For-Slug $bandSlug }
  if ($chapterSlug) { $chapterSlug = Sanitize-For-Slug $chapterSlug }

  $candidate = if ($bandSlug) { Join-Path $contentRootFull (Join-Path $bandSlug $chapterSlug) } else { Join-Path $contentRootFull $chapterSlug }

  try {
    $candidate = [System.IO.Path]::GetFullPath($candidate)
  } catch {
    $candidate = $candidate -replace '[\\/]+','\'
  }
  $candidate = $candidate.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)

  $maxTotal = 240
  if ($candidate.Length -le $maxTotal) { return $candidate }

  $bandLen = if ($bandSlug) { $bandSlug.Length } else { 0 }
  $maxChapterLen = [Math]::Max(6, ($maxTotal - ($contentRootFull.Length + 1 + $bandLen + 1)))
  if ($chapterSlug.Length -gt $maxChapterLen) {
    $chapterSlug = $chapterSlug.Substring(0,$maxChapterLen).TrimEnd('-')
  }

  $candidate = if ($bandSlug) { Join-Path $contentRootFull (Join-Path $bandSlug $chapterSlug) } else { Join-Path $contentRootFull $chapterSlug }
  try {
    $candidate = [System.IO.Path]::GetFullPath($candidate)
  } catch {
    $candidate = $candidate -replace '[\\/]+','\'
  }
  $candidate = $candidate.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
  return $candidate
}

function Write-Segment-Both {
  param(
    [string]$segmentHtml,
    [string]$targetDir,
    [switch]$DryRun
  )

  try { $targetDir = [System.IO.Path]::GetFullPath($targetDir) } catch { $targetDir = $targetDir -replace '[\\/]+','\' }
  $targetDir = $targetDir.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)

  $mdTarget = Join-Path $targetDir 'index.md'
  $htmlTarget = Join-Path $targetDir 'index.html'

  if ($DryRun) {
    try { $mdTargetFull = [System.IO.Path]::GetFullPath($mdTarget) } catch { $mdTargetFull = $mdTarget }
    try { $htmlTargetFull = [System.IO.Path]::GetFullPath($htmlTarget) } catch { $htmlTargetFull = $htmlTarget }
    try { $targetDirFull = [System.IO.Path]::GetFullPath($targetDir) } catch { $targetDirFull = $targetDir }

    Write-Output ('DryRun: targetDir = {0}' -f $targetDirFull)
    Write-Output ('DryRun: htmlTarget = {0}' -f $htmlTargetFull)
    Write-Output ('DryRun: mdTarget   = {0}' -f $mdTargetFull)
    Write-Output ('DryRun: targetDir.Length = {0} ; mdTarget.Length = {1} ; htmlTarget.Length = {2}' -f $targetDirFull.Length, $mdTargetFull.Length, $htmlTargetFull.Length)
    Write-Output ('DryRun: would write HTML to {0}' -f $htmlTargetFull)
    Write-Output ('DryRun: would generate MD to {0} from that HTML' -f $mdTargetFull)
    Write-Output ('DryRun: would (NOT) remove canonical index.md at {0}' -f $mdTargetFull)
    Write-Output ('DryRun: would (NOT) remove any other stray index.md/index.html under {0}' -f $targetDirFull)
    return @{ ok = $true }
  }

  Ensure-Dir -path $targetDir

  $backups = Make-Backups -mdPath $mdTarget -htmlPath $htmlTarget

  if (Test-Path $mdTarget) {
    try {
      attrib -R $mdTarget -ErrorAction SilentlyContinue
      attrib -H $mdTarget -ErrorAction SilentlyContinue
      attrib -S $mdTarget -ErrorAction SilentlyContinue
    } catch {}
    try {
      $mdCanonBak = $mdTarget + '.' + (Timestamp) + '.bak'
      Copy-Item -Path $mdTarget -Destination $mdCanonBak -Force -ErrorAction SilentlyContinue
      Remove-Item -Force -Path $mdTarget -ErrorAction Stop
      Write-Output ("Removed canonical existing markdown: {0} (backup: {1})" -f $mdTarget, $mdCanonBak)
    } catch {
      Write-Warning ("Could not remove canonical markdown {0}: {1}" -f $mdTarget, $_.Exception.Message)
    }
  }

  Remove-Existing-Targets -targetDir $targetDir

  try {
    Set-Content -Path $htmlTarget -Value $segmentHtml -Encoding utf8
    Write-Output ('Wrote HTML: {0}' -f $htmlTarget)
  } catch {
    Write-Warning ('Failed to write HTML {0}: {1}' -f $htmlTarget, $_.Exception.Message)
    Restore-Backups -backups $backups -mdPath $mdTarget -htmlPath $htmlTarget
    return @{ ok = $false; reason = 'write-html-failed' }
  }

  & pandoc $htmlTarget -f html -t gfm -o $mdTarget
  if ($LASTEXITCODE -ne 0) {
    Write-Warning ('pandoc failed for {0} (exit {1}). Removing created files and restoring backups if any.' -f $htmlTarget, $LASTEXITCODE)
    Safe-Remove -path $mdTarget
    Safe-Remove -path $htmlTarget
    Restore-Backups -backups $backups -mdPath $mdTarget -htmlPath $htmlTarget
    return @{ ok = $false; reason = 'pandoc-failed' }
  }

  Write-Output ('Wrote MD: {0}' -f $mdTarget)
  return @{ ok = $true }
}

# -----------------------------------------
# Sanity checks and prepare
# -----------------------------------------
if (-not (Test-Path $HtmlFile)) {
  Write-Error ('Master HTML not found: {0}' -f $HtmlFile)
  exit 1
}
if (-not (Get-Command pandoc -ErrorAction SilentlyContinue)) {
  Write-Error 'pandoc not found in PATH. Install pandoc or add it to PATH.'
  exit 1
}

if (Test-Path $TmpConverted) {
  Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $TmpConverted
}
New-Item -ItemType Directory -Path $TmpConverted -Force | Out-Null

# convert master HTML -> one markdown (keeps original behavior)
$mdOut = Join-Path $TmpConverted ([IO.Path]::GetFileNameWithoutExtension($HtmlFile) + '.md')
$mediaDir = Join-Path $TmpConverted 'media'

Write-Output ('Running pandoc: HTML -> Markdown')
pandoc $HtmlFile -f html -t gfm -o $mdOut --extract-media="$mediaDir" --wrap=preserve

if (-not (Test-Path $mdOut)) {
  Write-Error ('Pandoc conversion failed / output not found: {0}' -f $mdOut)
  exit 1
}
Write-Output ('Pandoc wrote: {0} ; media in: {1}' -f $mdOut, $mediaDir)

# -----------------------------------------
# Extraction: master (Vorwort, Schlussdialog) and Band files (Kapitel, Quellenverzeichnis)
# -----------------------------------------
$masterDir = Split-Path $HtmlFile -Parent
$contentAbs = (Resolve-Path '.\src\content').ProviderPath

# --- fixed-location band discovery: only check the three Band I/II/III subdirs for specific filenames ---
$bandFiles = @()
$bandSuffixes = @('I','II','III')
foreach ($s in $bandSuffixes) {
  $bandDirName = "Band $s"
  $bandDir = Join-Path $masterDir $bandDirName

  if (-not (Test-Path $bandDir)) {
    Write-Warning ("Band directory not found (skipping): {0}" -f $bandDir)
    continue
  }

  $candidates = @(
    ("Gedankenstreich_Band {0}.html" -f $s),
    ("Gedankenstreich-Band {0}.html" -f $s),
    ("Gedankenstreich_Band_{0}.html" -f $s),
    ("Gedankenstreich_Band{0}.html" -f $s),
    ("GedankenstreichBand{0}.html" -f $s)
  )

  $foundInBand = $false
  foreach ($fn in $candidates) {
    $fp = Join-Path $bandDir $fn
    if (Test-Path $fp) {
      $bandFiles += Get-Item $fp
      Write-Output ("Found band file: {0}" -f $fp)
      $foundInBand = $true
      break
    }
  }

  if (-not $foundInBand) {
    Write-Warning ("No expected band HTML found in {0}. Checked: {1}" -f $bandDir, ($candidates -join ', '))
  }
}

$bandFiles = $bandFiles | Sort-Object -Property FullName -Unique

if (-not $bandFiles -or $bandFiles.Count -eq 0) {
  Write-Warning ('No band HTML files found in the three fixed Band subdirectories under {0}.' -f $masterDir)
} else {
  Write-Output ('Using {0} band HTML file(s).' -f $bandFiles.Count)
}

# load master HTML text using auto-detect
$masterHtmlText = Read-File-AutoDetect -Path $HtmlFile
$masterSections = Get-H1-Sections -htmlText $masterHtmlText

function Process-Section {
  param(
    $sec,
    [string]$bandSlug,
    [switch]$DryRun
  )

  $titleNorm = Normalize-Title $sec.Title
  $h1Html = $sec.H1
  $segmentHtml = $masterHtmlText.Substring($sec.Start, $sec.End - $sec.Start).Trim()

  $targetDir = $null

  if ($titleNorm -imatch 'vorwort') {
    $chapterSlug = 'vorwort'
    $targetDir = Build-TargetDir -contentRoot $contentAbs -bandSlug 'gesamtwerk' -chapterSlug $chapterSlug
  } elseif ($titleNorm -imatch 'schlussdialog') {
    $chapterSlug = 'schlussdialog'
    $targetDir = Build-TargetDir -contentRoot $contentAbs -bandSlug 'gesamtwerk' -chapterSlug $chapterSlug
  } elseif ($bandSlug) {
    if ($titleNorm -match '(?i)\bkapitel\b.*?(\d{1,3})') {
      $num = $matches[1]
      $chapterSlug = ("kapitel-{0}" -f $num)
      $targetDir = Build-TargetDir -contentRoot $contentAbs -bandSlug $bandSlug -chapterSlug $chapterSlug
    } elseif ($titleNorm -match '(?i)quellenverzeichnis') {
      $chapterSlug = 'quellenverzeichnis'
      $targetDir = Build-TargetDir -contentRoot $contentAbs -bandSlug $bandSlug -chapterSlug $chapterSlug
    }
  }

  if (-not $targetDir) { return @{ found = $false } }

  Write-Output ('Processing section "{0}" -> target {1}' -f $sec.Title, $targetDir)

  # ensure removal of stray files before writing
  Remove-Existing-Targets -targetDir $targetDir

  $res = Write-Segment-Both -segmentHtml $segmentHtml -targetDir $targetDir -DryRun:$DryRun
  return @{ found = $true; result = $res }
}

# Process master: only Vorwort and Schlussdialog
Write-Output 'Extracting Vorwort and Schlussdialog from master HTML...'
foreach ($sec in $masterSections) {
  $titleClean = Clean-For-Match $sec.Title
  Write-Output ("Master H1 discovered: '{0}'" -f $sec.Title)
  Write-Output ("  cleaned: '{0}'" -f $titleClean)
  Write-Output ("  matchVorwort (contains): {0} ; matchSchlussdialog (contains): {1}" -f ($titleClean -like '*vorwort*'), ($titleClean -like '*schlussdialog*'))

  if ($titleClean -like '*vorwort*' -or $titleClean -like '*schlussdialog*') {
    $proc = Process-Section -sec $sec -bandSlug 'gesamtwerk' -DryRun:$DryRun
    if (-not $proc.found) { Write-Output ('Skipped master section: {0}' -f $sec.Title) }
  }
}

# Process band files: Kapitel + Quellenverzeichnis
foreach ($bf in $bandFiles) {
  Write-Output ('Processing band file: {0}' -f $bf.FullName)
  $bandSlug = Make-BandSlug -filePath $bf.FullName
  $bandHtml = Read-File-AutoDetect -Path $bf.FullName
  $sections = Get-H1-Sections -htmlText $bandHtml

  for ($i = 0; $i -lt $sections.Count; $i++) {
    $s = $sections[$i]
    $start = $s.Start
    if ($i -lt ($sections.Count - 1)) { $end = $sections[$i+1].Start } else { $end = $bandHtml.Length }
    $segmentHtml = $bandHtml.Substring($start, $end - $start).Trim()
    $titleNorm = Normalize-Title $s.Title

    $handle = $false
    if ($titleNorm -match '(?i)\bkapitel\b.*?(\d{1,3})') {
      $handle = $true
      $number = $matches[1]
      $chapterSlug = ("kapitel-{0}" -f $number)
      $targetDir = Build-TargetDir -contentRoot $contentAbs -bandSlug $bandSlug -chapterSlug $chapterSlug
    } elseif ($titleNorm -match '(?i)quellenverzeichnis') {
      $handle = $true
      $chapterSlug = 'quellenverzeichnis'
      $targetDir = Build-TargetDir -contentRoot $contentAbs -bandSlug $bandSlug -chapterSlug $chapterSlug
    }

    if (-not $handle) { continue }

    Write-Output ('Processing band section "{0}" -> {1}' -f $s.Title, $targetDir)

    $res = Write-Segment-Both -segmentHtml $segmentHtml -targetDir $targetDir -DryRun:$DryRun
    if (-not $res.ok) {
      Write-Warning ('Failed to write section {0} in band {1}: {2}' -f $s.Title, $bf.Name, $res.reason)
    }
  }
}

# -----------------------------------------
# Continue with existing flow: call splitter (unchanged) if requested
# -----------------------------------------
if ($RunSplitter) {
  $script = (Resolve-Path '.\scripts\split-md-into-chapters-force-utf8.ps1').ProviderPath
  $iconFile = (Resolve-Path '.\scripts\icons.json' -ErrorAction SilentlyContinue)
  $iconParam = ''
  if ($iconFile) { $iconParam = ("-IconMapFile {0}" -f $iconFile.ProviderPath) }

  $convertedAbs = (Resolve-Path $TmpConverted).ProviderPath
  $outAbs       = (Resolve-Path '.\scripts\split-logs').ProviderPath

  if ($DryRun) {
    Write-Output 'Running splitter (DryRun)...'
    & $script -ConvertedDir $convertedAbs -ContentDir $contentAbs -OutDir $outAbs -DryRun $iconParam *> .\scripts\pandoc-split-dryrun-output.txt
    Write-Output 'Splitter DryRun output saved to .\scripts\pandoc-split-dryrun-output.txt'
  } else {
    Write-Output 'Running splitter (apply)...'
    & $script -ConvertedDir $convertedAbs -ContentDir $contentAbs -OutDir $outAbs $iconParam *> .\scripts\pandoc-split-output.txt
    Write-Output 'Splitter output saved to .\scripts\pandoc-split-output.txt'
  }
}

Write-Output ('Done. Inspect {0} and split logs. (script version: v35)' -f $TmpConverted)