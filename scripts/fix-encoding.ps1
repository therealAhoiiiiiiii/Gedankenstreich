# scripts/fix-encoding.ps1
# Robust encoding repair for Markdown/MDX files under src/content/gesamtwerk
# - detects BOMs (UTF-8/UTF-16 LE/BE)
# - tries UTF-8, windows-1252, iso-8859-1
# - attempts a simple double-decode repair for common mojibake
# - writes files as UTF-8 without BOM
#
# Usage (from repo root):
#   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force; .\scripts\fix-encoding.ps1
# or
#   pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\fix-encoding.ps1

$root = "src\content\gesamtwerk"
if (!(Test-Path $root)) {
  Write-Error "Path not found: $root. Make sure you run this from the repo root and the path exists."
  exit 1
}

# collect files
$files = Get-ChildItem -Path $root -Recurse -Include *.md,*.mdx -File
if ($files.Count -eq 0) {
  Write-Host "No markdown files found under $root. Nothing to do."
  exit 0
}

$replacementChar = [char]0xFFFD
$stillBad = @()

# create UTF8 encoding without BOM once, reuse
$utf8NoBom = New-Object System.Text.UTF8Encoding -ArgumentList $false

foreach ($f in $files) {
  Write-Host "Processing: $($f.FullName)"
  try {
    $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
  } catch {
    Write-Warning "Could not read bytes for $($f.FullName): $_"
    continue
  }

  $text = $null
  $encodingDetected = "unknown"

  # BOM detection
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    # UTF-8 with BOM
    $text = [System.Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3)
    $encodingDetected = "utf8-with-bom"
  } elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
    # UTF-16 LE
    $text = [System.Text.Encoding]::Unicode.GetString($bytes, 2, $bytes.Length - 2)
    $encodingDetected = "utf16-le"
  } elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) {
    # UTF-16 BE
    $text = [System.Text.Encoding]::BigEndianUnicode.GetString($bytes, 2, $bytes.Length - 2)
    $encodingDetected = "utf16-be"
  } else {
    # try UTF-8 without BOM
    try {
      $text = [System.Text.Encoding]::UTF8.GetString($bytes)
      $encodingDetected = "utf8-no-bom"
    } catch {
      $text = $null
      $encodingDetected = "utf8-decode-failed"
    }
  }

  # if replacement chars present, try windows-1252 and iso-8859-1
  if ($text -ne $null -and $text -match $replacementChar) {
    try {
      $text_win = [System.Text.Encoding]::GetEncoding(1252).GetString($bytes)
    } catch {
      $text_win = $null
    }
    if ($text_win -ne $null -and $text_win -notmatch $replacementChar) {
      $text = $text_win
      $encodingDetected = "windows-1252 (recovered)"
    } else {
      try {
        $text_iso = [System.Text.Encoding]::GetEncoding("iso-8859-1").GetString($bytes)
      } catch {
        $text_iso = $null
      }
      if ($text_iso -ne $null -and $text_iso -notmatch $replacementChar) {
        $text = $text_iso
        $encodingDetected = "iso-8859-1 (recovered)"
      }
    }
  }

  # attempt simple double-decode repair when we see common mojibake indicators
  if ($text -ne $null -and $text -match 'Ã') {
    try {
      $bytesFromText = [System.Text.Encoding]::GetEncoding(1252).GetBytes($text)
      $repaired = [System.Text.Encoding]::UTF8.GetString($bytesFromText)
      if ($repaired -ne $null -and ($repaired -notmatch 'Ã') -and ($repaired -notmatch $replacementChar)) {
        $text = $repaired
        $encodingDetected += " + double-decode-repair"
      }
    } catch {
      # ignore
    }
  }

  # final fallback: windows-1252
  if ($text -eq $null) {
    try {
      $text = [System.Text.Encoding]::GetEncoding(1252).GetString($bytes)
      $encodingDetected = "windows-1252 (fallback)"
    } catch {
      Write-Warning "All decode attempts failed for $($f.FullName). Skipping file."
      continue
    }
  }

  # normalize line endings and remove BOM char if present
  $text = $text -replace "`r`n", "`n"
  if ($text.Length -gt 0 -and [int][char]$text[0] -eq 0xFEFF) {
    $text = $text.Substring(1)
  }

  # write back as UTF-8 without BOM using pre-created encoder
  try {
    [System.IO.File]::WriteAllText($f.FullName, $text, $utf8NoBom)
    Write-Host " -> written as UTF-8 (no BOM) [$encodingDetected]"
  } catch {
    Write-Warning "Write failed for $($f.FullName): $_"
    continue
  }
}

# final check for replacement character U+FFFD
foreach ($f in $files) {
  try {
    $content = [System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8)
  } catch {
    $content = ""
  }
  if ($content -match $replacementChar) {
    $stillBad += $f.FullName
  }
}

if ($stillBad.Count -gt 0) {
  Write-Host ""
  Write-Host "WARNING: The following files still contain U+FFFD (replacement char):"
  $stillBad | ForEach-Object { Write-Host " - $_" }
  Write-Host ""
  Write-Host "Please inspect these files manually or re-export from the original source."
} else {
  Write-Host ""
  Write-Host "No replacement characters found. All processed files are now UTF-8 (no BOM)."
  Write-Host ""
  Write-Host "Done. Restart your dev server (stop + npm run dev) and open /gesamtwerk."
}