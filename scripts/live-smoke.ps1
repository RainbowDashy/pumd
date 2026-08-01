[CmdletBinding()]
param(
  [string]$Moon = "moon"
)

$ErrorActionPreference = "Stop"

$repository = Split-Path -Parent $PSScriptRoot
$temporaryMarkdown = Join-Path ([System.IO.Path]::GetTempPath()) (
  "pumd-live-smoke-" + [System.Guid]::NewGuid().ToString("N") + ".md"
)

# This fixture deliberately exercises every supported native construct, including
# both kinds of link the Markdown renderer accepts.
$markdown = @'
# Pumd live smoke heading 1 🚀

## Pumd live smoke heading 2

### Pumd live smoke heading 3

#### Pumd live smoke heading 4

##### Pumd live smoke heading 5

###### Pumd live smoke heading 6

A **strong** and *emphasized* [direct link](https://example.com/direct) plus a [reference link][reference-target] with `inline code`.
Soft break stays in this paragraph.
Hard break follows here.__PUMD_HARD_BREAK__
第二行 with é.

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
$markdown = $markdown.Replace('__PUMD_HARD_BREAK__', '  ')

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

  # The readback test gets its ADC token through the project's googleauth
  # integration. The CLI above remains the only code that creates a document.
  $env:PUMD_LIVE_SMOKE_DOCUMENT_ID = $documentId
  $env:PUMD_LIVE_SMOKE_DOCUMENT_URL = $documentUrl
  $env:PUMD_LIVE_SMOKE_DOCUMENT_TITLE = [System.IO.Path]::GetFileNameWithoutExtension($temporaryMarkdown)
  Push-Location $repository
  try {
    & $Moon test --target native -p rainbowdashy/pumd/publish --include-skipped --filter "live smoke reads the CLI-created document"
    if ($LASTEXITCODE -ne 0) {
      throw "Google Docs readback test failed (exit $LASTEXITCODE)."
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
