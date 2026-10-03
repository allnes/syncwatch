param(
  [Parameter(Mandatory = $true)][string]$FFmpeg,
  [Parameter(Mandatory = $true)][string]$OutputDirectory,
  [ValidateSet('4k60', '8k30')][string]$Profile = '4k60',
  [ValidateRange(30, 1800)][int]$Seconds = 480
)

# Generate a reusable 30-second segment, then remux it into a longer fixture.
# Requires FFmpeg with Intel Quick Sync; generation must finish before profiling.
$ErrorActionPreference = 'Stop'
New-Item $OutputDirectory -ItemType Directory -Force | Out-Null
$size = if ($Profile -eq '4k60') { '3840x2160' } else { '7680x4320' }
$fps = if ($Profile -eq '4k60') { 60 } else { 30 }
$rate = if ($Profile -eq '4k60') { '80M' } else { '120M' }
$segment = Join-Path $OutputDirectory "$Profile-main10-pcm71-segment.mkv"
$output = Join-Path $OutputDirectory "$Profile-main10-pcm71.mkv"
if ((Test-Path $segment) -or (Test-Path $output)) { throw 'Use a fresh output directory' }
# Distinct quiet tones in all eight channels, with a low-frequency LFE signal.
# PCM preserves 96 kHz / 24 bit without confusing loudness with workload.
$tones = @(220, 277.18, 329.63, 60, 440, 554.37, 659.25, 880) |
  ForEach-Object { "0.025*sin(2*PI*$_*t)" }
$audio = "aevalsrc=$($tones -join '|'):s=96000:c=7.1"
$video = "testsrc2=size=${size}:rate=${fps},noise=alls=8:allf=t:all_seed=42,format=p010le"
& $FFmpeg -hide_banner -loglevel error -n -f lavfi -i $video -f lavfi -i $audio -t 30 `
  -map 0:v:0 -map 1:a:0 -c:v hevc_qsv -profile:v main10 -preset medium `
  -b:v $rate -maxrate $rate -bufsize $rate -g ($fps * 2) `
  -color_primaries bt709 -color_trc bt709 -colorspace bt709 `
  -c:a pcm_s24le -ar 96000 -ac 8 $segment
if ($LASTEXITCODE -ne 0) { throw 'Segment generation failed' }
& $FFmpeg -hide_banner -loglevel error -n -stream_loop -1 -i $segment -t $Seconds -map 0 -c copy $output
if ($LASTEXITCODE -ne 0) { throw 'Fixture remux failed' }
Write-Output $output
