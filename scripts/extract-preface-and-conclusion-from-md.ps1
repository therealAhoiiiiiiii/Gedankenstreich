<#
Extractor for Vorwort and Schlussdialog.
- Strict "heading-only" matching: we examine ONLY heading lines (markdown "#..." or HTML "<hN>...</hN>")
  and match the cleaned heading text against the configured label(s). We do NOT look beyond the heading
  line or perform any backward searches.
- Vorwort: search for heading text containing "KI und KI im Dialog"
- Schlussdialog: search for heading text containing "Schlussdialog"
- Preserves original slice (from heading line to next heading) when writing output so inline spans/icons remain.
- Safe by default: will NOT overwrite existing files unless -Force is passed.
- Creates a backup .bak_TIMESTAMP if overwriting.
- Respects -DryRun.

Usage:
pwsh .\scripts\extract-preface-and-conclusion-from-md.ps1 -MdFile '.\tmp\converted\Gedankenstreich_Gesamtwerk.md' -OutContentDir (Resolve-Path '.\src\content') -DryRun
pwsh .\scripts\extract-preface-and-conclusion-from-md.ps1 -MdFile '.\tmp\converted\Gedankenstreich_Gesamtwerk.md' -OutContentDir (Resolve-Path '.\src\content') -Force
#>

param(
  [Parameter(Mandatory=$true)][string]$MdFile,
  [Parameter(Mandatory=$true)][string]$OutContentDir,
  [switch]$DryRun,
  [switch]$Force
)

if (-not (Test-Path $MdFile)) { Write-Error "MdFile not found: $MdFile"; exit 1 }

# UTF-8 writer (no BOM)
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

# Read original markdown into lines
$origText = Get-Content -Raw -Encoding UTF8 -Path $MdFile
$lines = $origText -split "`r?`n"

function IsHeadingLine([string]$line) {
  return ($null -ne $line) -and ($line -match '^\s*#{1,6}\s+' -or $line -match '^\s*<h[1-6]\b[^>]*>')
}

function Clean-HeadingText([string]$headingLine) {
  # remove leading markdown hashes if present
  $text = $headingLine -replace '^\s*#{1,6}\s*',''

  # if HTML <hN>... found, strip tags but keep inner text
  if ($headingLine -match '^\s*<h([1-6])\b[^>]*>(.*?)</h\1>\s*$') {
    $text = $matches[2]
  }

  # remove any remaining inline HTML tags (e.g. spans)
  $text = $text -replace '<\/?[^>]+>',''

  # remove MSO bookmark artifacts like _Toc...
  $text = $text -replace '_Toc[0-9A-Za-z_-]+',''

  # decode HTML entities
  try { $text = [System.Net.WebUtility]::HtmlDecode($text) } catch {}

  # trim common formatting characters (safe TrimStart/TrimEnd to avoid regex issues)
  $removeChars = @('*','_',' ','-',[char]0x00A0)
  $text = $text.TrimStart($removeChars).TrimEnd($removeChars)

  # collapse whitespace
  $text = ($text -replace '\s+',' ').Trim()

  return $text
}

function Extract-Section-HeadingOnly([string[]]$linesArr, [string[]]$labels) {
  # For each heading line top-down, clean the heading and check if it contains any label.
  for ($i = 0; $i -lt $linesArr.Length; $i++) {
    if (IsHeadingLine $linesArr[$i]) {
      $clean = Clean-HeadingText $linesArr[$i]
      foreach ($lab in $labels) {
        if ($clean.Length -gt 0 -and $clean.ToLower().Contains($lab.ToLower())) {
          # found: extract from this heading to the next heading
          $startIdx = $i
          $nextHeading = $linesArr.Length
          for ($j = $startIdx + 1; $j -lt $linesArr.Length; $j++) {
            if (IsHeadingLine $linesArr[$j]) { $nextHeading = $j; break }
          }
          $slice = $linesArr[$startIdx..($nextHeading - 1)]
          return ($slice -join [Environment]::NewLine).Trim()
        }
      }
    }
  }
  return $null
}

# Targets: heading-only labels
$targets = @{
  'vorwort' = @('KI und KI im Dialog')
  'schlussdialog' = @('Schlussdialog')
}

foreach ($key in $targets.Keys) {
  $labels = $targets[$key]
  $section = Extract-Section-HeadingOnly $lines $labels

  if ($null -eq $section) {
    Write-Output "No section found for: $key"
    # debug: list lines that contain any of the labels (for inspection) -- this does not change extraction behavior
    foreach ($lab in $labels) {
      $found = @()
      for ($i=0; $i -lt $lines.Length; $i++) {
        if ($lines[$i].ToLower().Contains($lab.ToLower())) {
          $found += @{ Index = $i; Line = $lines[$i] }
        }
      }
      if ($found.Count -gt 0) {
        Write-Output "Lines containing '$lab' (index: line):"
        $found | ForEach-Object { "{0}: {1}" -f $_.Index, $_.Line } | ForEach-Object { Write-Output $_ }
      }
    }
    continue
  }

  $targetDir = Join-Path $OutContentDir ("gesamtwerk\" + $key)
  $indexPath = Join-Path $targetDir "index.md"
  $title = if ($key -eq 'vorwort') { 'Vorwort' } else { 'Schlussdialog' }

  $frontmatter = @"
---
title: "$title"
slug: "$key"
band: ""
order: 0
date: "$(Get-Date -Format yyyy-MM-dd)"
description: ""
---
"@

  $final = $frontmatter + "`n" + $section + "`n"

  if ($DryRun) {
    Write-Output "DRYRUN: Would write $indexPath (length: $($final.Length) chars)"
    continue
  }

  if ((Test-Path $indexPath -PathType Leaf) -and (-not $Force)) {
    Write-Output "SKIP: $indexPath already exists. Use -Force to overwrite."
    continue
  }

  if ((Test-Path $indexPath -PathType Leaf) -and $Force) {
    $ts = (Get-Date).ToString('yyyyMMdd_HHmmss')
    $bak = "$indexPath.bak_$ts"
    try {
      Copy-Item -Path $indexPath -Destination $bak -Force
      Write-Output "BACKUP: existing $indexPath -> $bak"
    } catch {
      Write-Warning "Could not create backup of $indexPath : $_"
    }
  }

  New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
  [System.IO.File]::WriteAllText($indexPath, $final, $utf8NoBom)
  Write-Output "Wrote $indexPath"
}

Write-Output "Done."