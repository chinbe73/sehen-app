param(
  [Parameter(Mandatory = $true)][string]$SourceDirectory,
  [Parameter(Mandatory = $true)][string]$OneDriveRoot,
  [Parameter(Mandatory = $true)][string]$BookId,
  [Parameter(Mandatory = $true)][string]$Title,
  [string]$Author = ""
)

$ErrorActionPreference = "Stop"
$appRoot = Join-Path $OneDriveRoot "Apps\Sehen"
$bookRoot = Join-Path $appRoot $BookId
New-Item -ItemType Directory -Force -Path $bookRoot | Out-Null

$chapters = Get-ChildItem -LiteralPath $SourceDirectory -Filter "*.m4b" |
  Where-Object { $_.BaseName -match " - (?<number>\d+) - Kapitel " } |
  Sort-Object { [int]([regex]::Match($_.BaseName, " - (\d+) - Kapitel ").Groups[1].Value) }
if (-not $chapters) { throw "Keine Libation-Kapiteldateien gefunden." }

$manifestChapters = @()
foreach ($source in $chapters) {
  $match = [regex]::Match($source.BaseName, " - (?<number>\d+) - Kapitel (?<title>.+)$")
  $number = [int]$match.Groups["number"].Value
  $chapterTitle = "Kapitel " + $match.Groups["title"].Value
  $fileName = "chapter-{0:D3}.m4b" -f $number
  $target = Join-Path $bookRoot $fileName
  if (-not (Test-Path -LiteralPath $target) -or (Get-Item -LiteralPath $target).Length -ne $source.Length) {
    Copy-Item -LiteralPath $source.FullName -Destination $target -Force
  }
  $manifestChapters += [ordered]@{
    title = $chapterTitle
    files = @("$BookId/$fileName")
  }
}

$mainBook = Get-ChildItem -LiteralPath $SourceDirectory -Filter "*.m4b" |
  Where-Object { $_.BaseName -notmatch " - \d+ - Kapitel " } |
  Sort-Object Length -Descending |
  Select-Object -First 1
$coverPath = Join-Path $bookRoot "cover.jpg"
if ($mainBook -and -not (Test-Path -LiteralPath $coverPath)) {
  & ffmpeg -hide_banner -loglevel error -y -i $mainBook.FullName -map 0:v:0 -frames:v 1 -- $coverPath
  if ($LASTEXITCODE -ne 0) { Remove-Item -LiteralPath $coverPath -ErrorAction SilentlyContinue }
}

$library = [ordered]@{
  version = 1
  updatedAt = (Get-Date).ToUniversalTime().ToString("o")
  activeBook = $BookId
  books = @([ordered]@{
    id = $BookId
    title = $Title
    author = $Author
    cover = if (Test-Path -LiteralPath $coverPath) { "$BookId/cover.jpg" } else { $null }
    chapters = $manifestChapters
  })
}
$library | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $appRoot "library.json") -Encoding utf8
Write-Host "Bereit für OneDrive: $($chapters.Count) Kapitel in $bookRoot"
