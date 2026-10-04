#!/bin/bash
set -euo pipefail
if [[ $# -lt 4 || $# -gt 5 ]]; then
  echo "Usage: $0 <media_kit_video directory> <app Contents/Frameworks> <Flutter framework parent with headers> <external output directory> [--expect-growth]" >&2
  exit 64
fi
root=$(cd "$(dirname "$0")/.." && pwd -P)
plugin=$(cd "$1" && pwd -P)
frameworks=$(cd "$2" && pwd -P)
flutter=$(cd "$3" && pwd -P)
mkdir -p "$4"
output=$(cd "$4" && pwd -P)
case "$output/" in "$root/"*) echo 'Keep generated artifacts outside the checkout.' >&2; exit 64;; esac
if [[ $# == 5 && "$5" != --expect-growth ]]; then exit 64; fi
for source in TextureHW.swift gl/OpenGLHelpers.swift gl/TextureGLContext.swift common/ResizableTextureProtocol.swift common/MPVHelpers.swift common/MPVVideoOutParams.swift common/SwappableObjectManager.swift; do
  { echo 'import Cocoa'; echo 'import OpenGL.GL3'; cat "$plugin/macos/Classes/plugin/$source"; } > "$output/$(basename "$source")"
done
cat > "$output/bridge.h" <<'HEADER'
#include <mpv/client.h>
#include <mpv/render.h>
#include <mpv/render_gl.h>
HEADER
cp "$root/tools/video/check_macos_texture_cache.swift" "$output/main.swift"
xcrun swiftc -O -import-objc-header "$output/bridge.h" \
  -I "$plugin/macos/Headers" -F "$flutter" -F "$frameworks" \
  -framework FlutterMacOS -framework Mpv -framework Cocoa -framework OpenGL \
  -Xlinker -rpath -Xlinker "$frameworks" \
  "$output/TextureHW.swift" "$output/OpenGLHelpers.swift" \
  "$output/TextureGLContext.swift" "$output/ResizableTextureProtocol.swift" \
  "$output/MPVHelpers.swift" "$output/MPVVideoOutParams.swift" \
  "$output/SwappableObjectManager.swift" "$output/main.swift" \
  -o "$output/check_macos_texture_cache"
"$output/check_macos_texture_cache" "${5:-}"
