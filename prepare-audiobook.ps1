param(
  [Parameter(Mandatory = $true)][string]$InputFile,
  [Parameter(Mandatory = $true)][string]$OutputDirectory,
  [Parameter(Mandatory = $true)][string]$BookId,
  [Parameter(Mandatory = $true)][string]$Title,
  [string]$Author = "",
  [int]$MaximumMinutes = 45
)

$ErrorActionPreference = "Stop"
$ffmpeg = Get-Command ffmpeg -ErrorAction Stop
$ffprobe = Get-Command ffprobe -ErrorAction Stop
$bookDirectory = Join-Path $OutputDirectory $BookId
New-Item -ItemType Directory -Force -Path $bookDirectory | Out-Null

$probeJson = & $ffprobe.Source -v error -show_chapters -show_format -of json -- $InputFile
$probe = $probeJson | ConvertFrom-Json
$sourceChapters = @($probe.chapters)
if ($sourceChapters.Count -eq 0) {
  $sourceChapters = @([pscustomobject]@{
    start_time = 0
    end_time = [double]$probe.format.duration
    tags = [pscustomobject]@{ title = "Hörbuch" }
  })
}

$manifestChapters = @()
$maximumSeconds = [Math]::Max(300, $MaximumMinutes * 60)
for ($chapterIndex = 0; $chapterIndex -lt $sourceChapters.Count; $chapterIndex++) {
  $chapter = $sourceChapters[$chapterIndex]
  $start = [double]$chapter.start_time
  $end = [double]$chapter.end_time
  $duration = [Math]::Max(0, $end - $start)
  $chapterTitle = if ($chapter.tags.title) { [string]$chapter.tags.title } else { "Kapitel $($chapterIndex + 1)" }
  $files = @()
  $part = 0
  for ($offset = 0.0; $offset -lt $duration; $offset += $maximumSeconds) {
    $part++
    $partDuration = [Math]::Min($maximumSeconds, $duration - $offset)
    $fileName = "chapter-{0:D3}-{1:D2}.m4a" -f ($chapterIndex + 1), $part
    $target = Join-Path $bookDirectory $fileName
    & $ffmpeg.Source -hide_banner -loglevel error -y -ss ($start + $offset) -i $InputFile -t $partDuration -map 0:a:0 -vn -c:a copy -- $target
    if ($LASTEXITCODE -ne 0) { throw "FFmpeg konnte $fileName nicht erstellen." }
    $files += "$BookId/$fileName"
  }
  $manifestChapters += [ordered]@{ title = $chapterTitle; files = $files }
}

$library = [ordered]@{
  version = 1
  updatedAt = (Get-Date).ToUniversalTime().ToString("o")
  activeBook = $BookId
  books = @([ordered]@{
    id = $BookId
    title = $Title
    author = $Author
    chapters = $manifestChapters
  })
}
$library | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $OutputDirectory "library.json") -Encoding utf8
Write-Host "Fertig: $($manifestChapters.Count) Kapitel in $bookDirectory"
