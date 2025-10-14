<#
Temporary test variant — Force UTF‑8 decoding only (no heuristics)

Usage (from repo root, DryRun recommended first):
& ".\scripts\split-md-into-chapters-force-utf8.ps1" -ConvertedDir ('E:\Uwe\WennKIaufKItrifft\Gesamtwerk') -ContentDir ('E:\Uwe\WennKIaufKItrifft\Dokumente\GitHub\Gedankenstreich\src\content') -OutDir ('E:\Uwe\WennKIaufKItrifft\Dokumente\GitHub\Gedankenstreich\scripts\split-logs') -DryRun -NormalizeParagraphs oder ohne Normalize (PreserveFormatting): -IconMapFile ('E:\Uwe\WennKIaufKItrifft\Dokumente\GitHub\Gedankenstreich\scripts\icons.json')
& ".\scripts\split-md-into-chapters-force-utf8.ps1" -ConvertedDir (Resolve-Path '.\Gesamtwerk') -ContentDir (Resolve-Path '.\src\content') -OutDir (Resolve-Path '.\scripts\split-logs') -DryRun -PreserveFormatting
This script is a minimal modification of your splitter that:
- reads every input file strictly as UTF-8 (BOM handled),
- writes a per-file log line "FORCE-UTF8: decoded as UTF-8" so you can verify what happened,
- does NOT attempt encoding heuristics or double-decode fallbacks.
Use this to confirm whether forcing UTF‑8 prevents the mojibake you observed.
Make a backup of the original script (or keep it under git) before replacing/using it.
#>

param(
  [switch]$PreserveFormatting,
  [switch]$NormalizeParagraphs,
  [Parameter(Mandatory=$true)][string]$ConvertedDir,
  [Parameter(Mandatory=$true)][string]$ContentDir,
  [string]$HeadingRegex = '^#\s+',
  [string]$ChapterHeadingRegex = '(?i)^\s*(Kapitel\s*\d+|Kapitel\b)',
  [string]$OutDir = ".\split-logs",
  [switch]$DryRun,
  [int]$MaxStepsOverride = 0,
  [string]$IconMapFile
)

# Encoding object once (UTF8 without BOM) for writing
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Slugify([string]$s) {
  if ($null -eq $s) { return "" }
  $s = $s.Trim().ToLowerInvariant()
  $s = $s -replace '[äÄ]', 'ae'
  $s = $s -replace '[öÖ]', 'oe'
  $s = $s -replace '[üÜ]', 'ue'
  $s = $s -replace '[ß]', 'ss'
  $s = $s -replace '[^a-z0-9\s-]', ''
  $s = $s -replace '\s+', '-'
  return $s.Trim('-')
}

function CleanTitle([string]$s) {
  if ($null -eq $s) { return "" }
  $s = $s -replace '<[^>]+>', ''
  $s = $s -replace '^\s*#+\s*', ''
  $s = $s.Trim()
  $s = $s -replace '^\*+',''
  $s = $s -replace '\*+$',''
  $s = $s -replace '^_+',''
  $s = $s -replace '_+$',''
  $s = $s -replace '\*\*',''
  $s = $s -replace '\*',''
  $s = $s -replace '\s+',' '
  return $s.Trim()
}

function BandInfoFromRoman([string]$roman) {
  if ($null -eq $roman) { return @{Num='';Name=''} }
  switch ($roman.ToUpper()) {
    'I' { return @{Num='1';Name='die-erschoepfte-republik'} }
    'II' { return @{Num='2';Name='mensch-und-computer'} }
    'III' { return @{Num='3';Name='loslassen-und-neuwagen'} }
    default { return @{Num='';Name=''} }
  }
}

# ----------------- Icon map loading (unchanged) -----------------
$iconMap = @{}
if ($PSBoundParameters.ContainsKey('IconMapFile') -and $IconMapFile -and (Test-Path $IconMapFile)) {
  try {
    $json = Get-Content -Raw -Path $IconMapFile -Encoding UTF8
    $obj = ConvertFrom-Json $json
    foreach ($p in $obj.PSObject.Properties) { $iconMap[$p.Name] = $p.Value }
    Write-Output "Loaded icon map with $($iconMap.Count) entries from $IconMapFile"
  } catch {
    Write-Warning "Could not load icon map file '$IconMapFile': $_. Continuing without icon replacements."
  }
} else {
  Write-Output "No IconMapFile provided or not found; skipping icon replacements. To enable, provide -IconMapFile '.\scripts\icons.json' (UTF-8 without BOM)."
}

function Apply-IconMap([string]$text, [hashtable]$map) {
  if ($null -eq $text -or $map.Count -eq 0) { return $text }
  foreach ($k in $map.Keys) {
    if ($text.IndexOf($k) -ge 0) {
      $text = $text.Replace($k, [string]$map[$k])
    }
  }
  return $text
}

# ----------------- End helpers -----------------

# Normalize paths early
$ConvertedDir = (Resolve-Path $ConvertedDir).ProviderPath
# Ensure ContentDir exists so Resolve-Path works in DryRun
New-Item -ItemType Directory -Path $ContentDir -Force | Out-Null
$ContentDir = (Resolve-Path $ContentDir).ProviderPath
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

# Safety: converted must not be inside content
if ($ConvertedDir.StartsWith($ContentDir, [System.StringComparison]::InvariantCultureIgnoreCase)) {
  Write-Error "ABORT: ConvertedDir is inside ContentDir. This would cause re-import loops. Move one of them."
  return
}

Write-Output "ConvertedDir: $ConvertedDir"
Write-Output "ContentDir:   $ContentDir"
Write-Output "HeadingRegex: $HeadingRegex"
Write-Output "ChapterHeadingRegex: $ChapterHeadingRegex"
Write-Output "OutDir:       $(Resolve-Path $OutDir)"
if ($DryRun) { Write-Output "DRY RUN mode - no files will be written." }

# Build a static list of input files: only .md and .txt — skip .docx and any other types
$allFiles = Get-ChildItem -Path $ConvertedDir -Recurse -File | Sort-Object FullName
# Filter allowed extensions (case-insensitive)
$inputFiles = $allFiles | Where-Object { $_.Extension -in '.md', '.txt' }
$skippedCount = ($allFiles.Count - $inputFiles.Count)

Write-Output "Found $($allFiles.Count) total file(s) under ConvertedDir; processing $($inputFiles.Count) (.md/.txt), skipping $skippedCount others (e.g. .docx)."

$mdFiles = $inputFiles
$mdCount = $mdFiles.Count

if ($mdCount -eq 0) { Write-Warning "No .md or .txt files found. Exiting."; return }

$maxSteps = if ($MaxStepsOverride -gt 0) { $MaxStepsOverride } else { [math]::Max(1000, $mdCount * 20) }
$step = 0

# global chapter counter across the whole import (1..N)
$globalChapterCounter = 0

foreach ($md in $mdFiles) 
{
    $step++
    if ($step -gt $maxSteps) {
        Write-Error "MaxSteps ($maxSteps) exceeded - aborting to prevent infinite loop."
        break
    }

    Write-Output "[$step/$mdCount] Processing: $($md.FullName)"
    $log = Join-Path $OutDir ("split-" + ($md.BaseName -replace '\s+','_') + ".log")
    "==== Splitting $($md.FullName) ($(Get-Date)) ====" | Out-File $log -Encoding utf8

    # --- robuster FORCE-UTF8/UTF16-Decoder (BOMs + heuristic) ---
    $bytes = [System.IO.File]::ReadAllBytes($md.FullName)

    $decodedEncoding = "unknown"
  try {
    # BOM detection (UTF-8 / UTF-16LE / UTF-16BE)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
      $text = [System.Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3)
      $decodedEncoding = "utf-8 (bom)"
    } elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
      # UTF-16 LE BOM
      $text = [System.Text.Encoding]::Unicode.GetString($bytes, 2, $bytes.Length - 2)
      $decodedEncoding = "utf-16le (bom)"
    } elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) {
      # UTF-16 BE BOM
      $text = [System.Text.Encoding]::BigEndianUnicode.GetString($bytes, 2, $bytes.Length - 2)
      $decodedEncoding = "utf-16be (bom)"
    } else {
      # Heuristik: prüfe, ob viele Null-Bytes in geraden/ungeraden Positionen vorkommen -> wahrscheinlich UTF-16LE
      $len = [math]::Min(1000, $bytes.Length)
      $zeroEven = 0
      $zeroOdd = 0
      for ($i = 0; $i -lt $len; $i++) {
        if ($bytes[$i] -eq 0) {
          if (($i % 2) -eq 0) { $zeroEven++ } else { $zeroOdd++ }
        }
      }
      # Wenn >=30% der geprüften Bytes NUL sind und fast alle auf gerade oder ungerade Index fallen, vermuten wir UTF-16LE/BE
      if ($len -gt 10 -and ($zeroEven -gt ($len * 0.25) -or $zeroOdd -gt ($len * 0.25))) {
        if ($zeroOdd -gt $zeroEven) {
          $text = [System.Text.Encoding]::BigEndianUnicode.GetString($bytes)
          $decodedEncoding = "utf-16be (heuristic)"
        } else {
          $text = [System.Text.Encoding]::Unicode.GetString($bytes)
          $decodedEncoding = "utf-16le (heuristic)"
        }
      } else {
        # Fallback: UTF-8 (no BOM)
        $text = [System.Text.Encoding]::UTF8.GetString($bytes)
        $decodedEncoding = "utf-8 (fallback)"
      }
    }

    # Log which encoding we chose
    ("DECODED-AS: " + $decodedEncoding) | Tee-Object -FilePath $log -Append
    Write-Output "DECODED-AS: $decodedEncoding for $($md.Name)"

    "Found $($chunks.Count) chunk(s) in $($md.Name)" | Tee-Object -FilePath $log -Append

    # Combine into final chunks but only treat ones matching ChapterHeadingRegex as chapters
    $finalChunks = @()
    $currentFinal = $null
    $currentBand = ''   # roman 'I','II','III' or '' if unknown

    foreach ($c in $chunks) {
      $m = [regex]::Match($c.Title, '(?i)Band\s*(I{1,3})')
      if ($m.Success) { $currentBand = $m.Groups[1].Value }

      $m2 = [regex]::Match($c.Title, '(?i)Titelblatt\s+Band\s*(I{1,3})')
      if ($m2.Success) { $currentBand = $m2.Groups[1].Value }

      $m3 = [regex]::Match($c.Title, '(?i)Inhaltsverzeichnis\s+Band\s*(I{1,3})')
      if ($m3.Success) { $currentBand = $m3.Groups[1].Value }

      if ($c.Title -match $ChapterHeadingRegex) {
        $globalChapterCounter++
        $currentFinal = [PSCustomObject]@{ Title = $c.Title; Content = $c.Content; Type='chapter'; Band=$currentBand; GlobalIndex=$globalChapterCounter }
        $finalChunks += $currentFinal
      } else {
        $t = $c.Title
        if ($t -match '(?i)^\s*Titelblatt') {
          $f = [PSCustomObject]@{ Title = $t; Content = $c.Content; Type='titlepage'; Band=$currentBand }
          $finalChunks += $f
          $m4 = [regex]::Match($t, '(?i)Band\s*(I{1,3})')
          if ($m4.Success) { $currentBand = $m4.Groups[1].Value }
        } elseif ($t -match '(?i)^\s*Inhaltsverzeichnis') {
          $f = [PSCustomObject]@{ Title = $t; Content = $c.Content; Type='toc'; Band=$currentBand }
          $finalChunks += $f
        } elseif ($t -match '(?i)^\s*Anhang') {
          $f = [PSCustomObject]@{ Title = $t; Content = $c.Content; Type='appendix'; Band=$currentBand }
          $finalChunks += $f
        } elseif ($t -match '(?i)^\s*Quellenverzeichnis|^(?i)^\s*Quellen') {
          $f = [PSCustomObject]@{ Title = $t; Content = $c.Content; Type='sources'; Band=$currentBand }
          $finalChunks += $f
        } elseif ($t -match '(?i)^\s*Schlussdialog') {
          $f = [PSCustomObject]@{ Title = $t; Content = $c.Content; Type='schlussdialog'; Band=$currentBand }
          $finalChunks += $f
        } elseif ($t -match '(?i)^\s*Widmung' -or $t -match '(?i)^\s*Zitat') {
          "Skipping special global item (Widmung/Zitat): $t" | Tee-Object -FilePath $log -Append
          continue
        } else {
          if ($null -ne $currentFinal -and $currentFinal.Type -eq 'chapter') {
            $currentFinal.Content += "`n`n" + $c.Content
          } else {
            $vorwort = $finalChunks | Where-Object { $_.Type -eq 'vorwort' } | Select-Object -First 1
            if (-not $vorwort) {
              $vorwort = [PSCustomObject]@{ Title='Vorwort'; Content=$c.Content; Type='vorwort'; Band=$currentBand }
              $finalChunks = ,$vorwort + $finalChunks
            } else {
              $vorwort.Content += "`n`n" + $c.Content
            }
          }
        }
      }
    } # end foreach $chunks

    "After combining: $($finalChunks.Count) final chunk(s) will be emitted." | Tee-Object -FilePath $log -Append

    foreach ($c in $finalChunks) {
      $type = $c.Type
      $bandRoman = $c.Band
      $bandInfo = BandInfoFromRoman($bandRoman)
      $bandNum = $bandInfo.Num
      $bandName = $bandInfo.Name

      switch ($type) {
        'chapter' {
          $order = $c.GlobalIndex
          $slug = ("kapitel-{0:00}" -f $order)
          $title = CleanTitle $c.Title
          $outDirForChunk = Join-Path $ContentDir $slug
          $frontBand = if ($bandNum -ne '') { "Band $bandRoman" } else { "" }
        }
        'titlepage' {
          $title = CleanTitle $c.Title
          if ($bandNum -ne '') { $slug = "band$bandNum-titelblatt" } else { $slug = "titelblatt" }
          $outDirForChunk = Join-Path $ContentDir $slug
          $order = 0
          $frontBand = if ($bandNum -ne '') { "Band $bandRoman" } else { "" }
        }
        'toc' {
          $title = CleanTitle $c.Title
          if ($bandNum -ne '') { $slug = "band$bandNum-inhaltsverzeichnis" } else { $slug = "inhaltsverzeichnis" }
          $outDirForChunk = Join-Path $ContentDir $slug
          $order = 0
          $frontBand = if ($bandNum -ne '') { "Band $bandRoman" } else { "" }
        }
        'appendix' {
          $title = CleanTitle $c.Title
          if ($bandNum -ne '') { $slug = "band$bandNum-anhang" } else { $slug = "anhang" }
          $outDirForChunk = Join-Path $ContentDir $slug
          $order = 0
          $frontBand = if ($bandNum -ne '') { "Band $bandRoman" } else { "" }
        }
        'sources' {
          $title = CleanTitle $c.Title
          if ($bandNum -ne '') { $slug = "band$bandNum-quellenverzeichnis" } else { $slug = "quellenverzeichnis" }
          $outDirForChunk = Join-Path $ContentDir $slug
          $order = 0
          $frontBand = if ($bandNum -ne '') { "Band $bandRoman" } else { "" }
        }
        'schlussdialog' {
          $title = CleanTitle $c.Title
          $slug = "gesamtwerk-schlussdialog"
          $outDirForChunk = Join-Path $ContentDir "gesamtwerk\$slug"
          $order = 0
          $frontBand = ""
        }
        'vorwort' {
          $title = CleanTitle $c.Title
          $slug = "vorwort"
          $outDirForChunk = Join-Path $ContentDir "gesamtwerk\$slug"
          $order = 0
          $frontBand = ""
        }
        default {
          $title = CleanTitle $c.Title
          $slug = Slugify($title)
          $outDirForChunk = Join-Path $ContentDir $slug
          $order = 0
          $frontBand = ""
        }
      } # end switch

      "Emit: Type=$type Title='$title' Slug='$slug' -> $outDirForChunk (order $order) Band='$frontBand'" | Tee-Object -FilePath $log -Append

      if ($DryRun) { continue }

      # create dirs and copy images
      $mediaDir = Join-Path $outDirForChunk "media"
      New-Item -ItemType Directory -Path $mediaDir -Force | Out-Null

      $imgPaths = @()
      $mdImgRx = [regex]::new('!\[[^\]]*\]\(([^)]+)\)')
      foreach ($m in ($mdImgRx.Matches($c.Content))) { $imgPaths += $m.Groups[1].Value }
      $htmlImgRx = [regex]::new('<img\s+[^>]*src=["'']([^"'']+)["''][^>]*>', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
      foreach ($m in ($htmlImgRx.Matches($c.Content))) { $imgPaths += $m.Groups[1].Value }

      $imgPaths = $imgPaths | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' } | Select-Object -Unique

      foreach ($p in $imgPaths) {
        $fname = Split-Path -Path $p -Leaf
        $found = Get-ChildItem -Path $ConvertedDir -Recurse -File -Filter $fname -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -ne $found) {
          $dest = Join-Path $mediaDir $found.Name
          Copy-Item -Path $found.FullName -Destination $dest -Force
          "Copied image $($found.FullName) -> $dest" | Tee-Object -FilePath $log -Append
          $escaped = [regex]::Escape($p)
          $c.Content = [regex]::Replace($c.Content, $escaped, ("./media/" + $found.Name))
        } else {
          "WARN: image $p not found under $ConvertedDir" | Tee-Object -FilePath $log -Append
        }
      }

      $date = (Get-Date).ToString("yyyy-MM-dd")
      $frontmatter = ("---`n")
      $frontmatter += ("title: " + '"' + $title + '"' + "`n")
      $frontmatter += ("slug: " + '"' + $slug + '"' + "`n")
      $frontmatter += ("band: " + '"' + $frontBand + '"' + "`n")
      $frontmatter += ("order: " + $order + "`n")
      $frontmatter += ("date: " + '"' + $date + '"' + "`n")
      $frontmatter += ("description: " + '""' + "`n")
      $frontmatter += ("---`n`n")

      $indexPath = Join-Path $outDirForChunk "index.md"
          # --- Debug: show small before/after snippets in the log ---
      # Pre-save snippet (first 200 chars)
      $preSnippet = if ($null -ne $c.Content) { $c.Content.Substring(0, [math]::Min(200, $c.Content.Length)) } else { "" }
      ("PRE-SAVE SNIPPET: " + $preSnippet) | Tee-Object -FilePath $log -Append

      # Normalize paragraphs (optional) — convert single line wraps into real markdown paragraphs
      if (-not $PreserveFormatting -and $NormalizeParagraphs) {
        # normalize CRLF/LF to LF first
        $tmp = $c.Content -replace "`r`n", "`n"
        $tmp = $tmp -replace "`r", "`n"

        # Insert an extra newline between two non-empty lines, except when the next line looks like a markdown structural element:
        #   - headings (#)
        #   - lists (-, *, + or numbered "1.")
        #   - blockquote (>)
        #   - code fence (```), or lines starting with 4 spaces (indented code)
        # This regex: replace single LF between two non-space chars with two LFs unless the following line starts with a markdown marker.
        $tmp = [regex]::Replace($tmp, '(?<=\S)\n(?!\s*(?:#|[-+*]|\d+\.)|\s*$)', "`n`n", [System.Text.RegularExpressions.RegexOptions]::Multiline)

        # restore system newlines
        $c.Content = $tmp -replace "`n", [Environment]::NewLine
      } else {
        # If we preserve formatting, still normalize to system newlines to avoid mixed CRLF/LF
        $c.Content = $c.Content -replace "`r`n", [Environment]::NewLine
        $c.Content = $c.Content -replace "`n", [Environment]::NewLine
      }

      # Post‑change snippet (first 200 chars)
      $postSnippet = if ($null -ne $c.Content) { $c.Content.Substring(0, [math]::Min(200, $c.Content.Length)) } else { "" }
      ("POST-SAVE SNIPPET: " + $postSnippet) | Tee-Object -FilePath $log -Append

      # Now write the file as before
      $indexPath = Join-Path $outDirForChunk "index.md"
      [System.IO.File]::WriteAllText($indexPath, $frontmatter + $c.Content, $utf8NoBom)

      "Wrote $indexPath" | Tee-Object -FilePath $log -Append
    } # end foreach finalChunks

  } catch {
    $_ | Out-String | Tee-Object -FilePath $log -Append
    Write-Warning "Exception while processing $($md.FullName) - see $log"
  } finally {
    "Finished $($md.Name) at $(Get-Date)" | Tee-Object -FilePath $log -Append
  }

} # end foreach mdFiles

Write-Output "Processing complete. Logs in: $(Resolve-Path $OutDir)"
