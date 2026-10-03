# Resize lifetime and diagnostic latency

This round uses the same physical cameras, Windows/Mac hosts and generated
4K60 HEVC Main10 + 7.1 PCM fixture described in the [parent report](../README.md).
The starting application commit is `937c02f`.

## Native surface regression

The `media_kit_video 2.0.1` Windows ANGLE manager creates an untracked GL texture
on every resize. That binding retains the old pbuffer allocation until context
teardown. The rendering path uses the pbuffer framebuffer and a DXGI copy, so
the extra GL texture is unnecessary.

`tool/native_surface_probe` alternates 960×540 and 1920×1080 sixty times in a
fresh process. Every iteration clears the framebuffer and checks its pixel
against RGBA (51, 102, 153, 255), with one unit of RGB rounding tolerance.
Both builds pass every color assertion and exit with code 0.

| Metric | Original dependency | Patched dependency |
| --- | ---: | ---: |
| Initial private memory | 70.33 MiB | 70.31 MiB |
| Private memory after 60 resizes | 499.21 MiB | 83.99 MiB |
| Live GL textures after 60 resizes | 60 | 0 |

The patched process reaches a plateau rather than retaining one surface per
resize. These are isolated native-surface figures, not whole-application RAM.
Raw observations: [original](baseline-surface.csv), [patched](patched-surface.csv).
The isolated dependency preparation is idempotent and its Windows release
build succeeds. Full application comparisons are recorded below once complete.
