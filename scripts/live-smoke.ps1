[CmdletBinding()]
param(
  [string]$Moon = "moon",
  [switch]$ValidateFixtureOnly
)

$ErrorActionPreference = "Stop"

# This fixture deliberately exercises every supported native construct, including
# both kinds of link the Markdown renderer accepts.
$markdown = @'
# Pumd live smoke heading 1 __PUMD_ROCKET__

## Pumd live smoke heading 2

### Pumd live smoke heading 3

#### Pumd live smoke heading 4

##### Pumd live smoke heading 5

###### Pumd live smoke heading 6

A **strong** and *emphasized* [direct link](https://example.com/direct) plus a [reference link][reference-target] with `inline code`.
Soft break stays in this paragraph.
Hard break follows here.__PUMD_HARD_BREAK__
__PUMD_CJK_LINE__ with e__PUMD_COMBINING_ACUTE__.

```text
fenced code
```

3. ordered item
   - nested item

- bullet item

| Header | Right |
| --- | ---: |
| Cell | [linked](https://example.com/table) |

[reference-target]: https://example.com/reference "Reference link"
'@
$rocket = [char]::ConvertFromUtf32(0x1F680)
$cjkLine = -join ([char]0x7B2C, [char]0x4E8C, [char]0x884C)
$combiningAcute = [char]0x0301
$markdown = $markdown.Replace('__PUMD_ROCKET__', $rocket)
$markdown = $markdown.Replace('__PUMD_CJK_LINE__', $cjkLine)
$markdown = $markdown.Replace('__PUMD_COMBINING_ACUTE__', $combiningAcute)
$markdown = $markdown.Replace('__PUMD_HARD_BREAK__', '  ')

if ($ValidateFixtureOnly) {
  $expectedUnicodeLine = "$cjkLine with e$combiningAcute."
  $unicodeLines = @($markdown -split "`r?`n" | Where-Object { $_ -like '*with e*' })
  if ($unicodeLines.Count -ne 1 -or $unicodeLines[0] -cne $expectedUnicodeLine) {
    throw "Unicode fixture line did not match the expected content."
  }

  $actualLineCodeUnits = @($unicodeLines[0].ToCharArray() | ForEach-Object { [int]$_ })
  $expectedLineCodeUnits = @(
    0x7B2C, 0x4E8C, 0x884C, 0x0020, 0x0077, 0x0069,
    0x0074, 0x0068, 0x0020, 0x0065, 0x0301, 0x002E
  )
  if ($actualLineCodeUnits.Count -ne $expectedLineCodeUnits.Count) {
    throw "Unicode fixture line had $($actualLineCodeUnits.Count) code units; expected $($expectedLineCodeUnits.Count)."
  }
  for ($index = 0; $index -lt $expectedLineCodeUnits.Count; $index++) {
    if ($actualLineCodeUnits[$index] -ne $expectedLineCodeUnits[$index]) {
      throw "Unicode fixture line code unit $index was $($actualLineCodeUnits[$index].ToString('X4')); expected $($expectedLineCodeUnits[$index].ToString('X4'))."
    }
  }

  $privateUseCodeUnits = @(
    $markdown.ToCharArray() | Where-Object {
      [int]$_ -ge 0xE000 -and [int]$_ -le 0xF8FF
    }
  )
  if ($privateUseCodeUnits.Count -ne 0) {
    $privateUseCodeUnit = [int]$privateUseCodeUnits[0]
    throw "Fixture contains BMP private-use code unit $($privateUseCodeUnit.ToString('X4')), which Google Docs strips."
  }

  $rocketCodeUnits = @($rocket.ToCharArray() | ForEach-Object { [int]$_ })
  if (
    $rocketCodeUnits.Count -ne 2 -or
    $rocketCodeUnits[0] -ne 0xD83D -or
    $rocketCodeUnits[1] -ne 0xDE80 -or
    -not $markdown.Contains("# Pumd live smoke heading 1 $rocket")
  ) {
    throw "Rocket fixture did not contain the expected UTF-16 surrogate pair."
  }

  $hardBreakLines = @($markdown -split "`r?`n" | Where-Object { $_ -like 'Hard break follows here.*' })
  if ($hardBreakLines.Count -ne 1 -or $hardBreakLines[0] -cne 'Hard break follows here.  ') {
    throw "Hard-break fixture did not retain its two trailing spaces."
  }

  if ($markdown.Contains('__PUMD_')) {
    throw "Fixture still contains an unreplaced sentinel token."
  }

  Write-Host "Live smoke fixture validation passed."
  return
}

$repository = Split-Path -Parent $PSScriptRoot
$temporaryMarkdown = Join-Path ([System.IO.Path]::GetTempPath()) (
  "pumd-live-smoke-" + [System.Guid]::NewGuid().ToString("N") + ".md"
)

try {
  [System.IO.File]::WriteAllText(
    $temporaryMarkdown,
    $markdown,
    [System.Text.UTF8Encoding]::new($false)
  )

  Push-Location $repository
  try {
    # Windows PowerShell wraps redirected native stderr as non-terminating
    # ErrorRecord values. Keep collecting that output so the explicit exit-code
    # check below can report the complete Moon failure.
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
      $publishOutput = & $Moon run cmd/pumd -- publish $temporaryMarkdown 2>&1
      $publishExitCode = $LASTEXITCODE
    }
    finally {
      $ErrorActionPreference = $previousErrorActionPreference
    }
  }
  finally {
    Pop-Location
  }

  $publishText = ($publishOutput | ForEach-Object { $_.ToString() }) -join "`n"
  if ($publishExitCode -ne 0) {
    throw "pumd publish failed (exit $publishExitCode):`n$publishText"
  }

  $idMatch = [regex]::Match($publishText, '(?m)^document ID:\s*(?<id>[^\s]+)\s*$')
  $urlMatch = [regex]::Match($publishText, '(?m)^edit URL:\s*(?<url>https://docs\.google\.com/document/d/[^\s]+/edit)\s*$')
  if (-not $idMatch.Success -or -not $urlMatch.Success) {
    throw "pumd publish did not print its document ID and canonical edit URL:`n$publishText"
  }

  $documentId = $idMatch.Groups['id'].Value
  $documentUrl = $urlMatch.Groups['url'].Value
  $expectedUrl = "https://docs.google.com/document/d/$documentId/edit"
  if ($documentUrl -ne $expectedUrl) {
    throw "pumd printed a URL for a different document: $documentUrl"
  }

  Write-Host "REAL GOOGLE DOC CREATED: $documentUrl"

  # The readback test gets its ADC token through the project's googleauth
  # integration. The CLI above remains the only code that creates a document.
  $env:PUMD_LIVE_SMOKE_DOCUMENT_ID = $documentId
  $env:PUMD_LIVE_SMOKE_DOCUMENT_URL = $documentUrl
  $env:PUMD_LIVE_SMOKE_DOCUMENT_TITLE = [System.IO.Path]::GetFileNameWithoutExtension($temporaryMarkdown)
  Push-Location $repository
  try {
    & $Moon test --target native -p rainbowdashy/pumd/publish --include-skipped --filter "live smoke reads the CLI-created document"
    if ($LASTEXITCODE -ne 0) {
      throw "Google Docs readback test failed for $documentUrl (exit $LASTEXITCODE)."
    }
  }
  finally {
    Pop-Location
  }

  Write-Host "Live smoke passed: $documentUrl"
}
finally {
  Remove-Item -LiteralPath $temporaryMarkdown -Force -ErrorAction SilentlyContinue
}
