# Preview seek fixture

`preview_colors.mp4` contains three one-second, solid-color sections: red, green,
and blue, at 64×36 / 10 fps. It has no audio. The native preview test seeks in
both directions and opens at a nonzero position, checking the decoded thumbnail
color to catch stale frames. Lossless x264 uses the High 4:4:4 Predictive profile
even with this 4:2:0 pixel format. Keep it: it also catches a Windows QSV decoder
that returned corrupt pixels instead of falling back for this profile.

Generate with FFmpeg:

```sh
ffmpeg -f lavfi -i color=red:s=64x36:r=10:d=1 \
  -f lavfi -i color=lime:s=64x36:r=10:d=1 \
  -f lavfi -i color=blue:s=64x36:r=10:d=1 \
  -filter_complex '[0:v][1:v][2:v]concat=n=3:v=1:a=0' \
  -c:v libx264 -preset ultrafast -crf 0 -g 10 -pix_fmt yuv420p preview_colors.mp4
```
