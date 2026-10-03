#include "angle_surface_manager.h"

#include <psapi.h>
#include <cstdlib>
#include <iostream>

// Run in a fresh process before and after applying the native surface patch.
// Assert framebuffer correctness while recording retained allocations on resize.
int main() {
  ANGLESurfaceManager surface(960, 540);
  std::cout << "iteration,liveTextures,privateBytes,workingSetBytes\n";
  for (int i = 0; i <= 60; ++i) {
    surface.SetSize(i % 2 ? 1920 : 960, i % 2 ? 1080 : 540);
    surface.Draw([] {
      glClearColor(0.2f, 0.4f, 0.6f, 1.0f);
      glClear(GL_COLOR_BUFFER_BIT);
    });
    surface.MakeCurrent(true);
    unsigned char pixel[4]{};
    glReadPixels(0, 0, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel);
    if (std::abs(int(pixel[0]) - 51) > 1 ||
        std::abs(int(pixel[1]) - 102) > 1 ||
        std::abs(int(pixel[2]) - 153) > 1 || pixel[3] != 255) {
      std::cerr << "Unexpected framebuffer color at iteration " << i << '\n';
      return 2;
    }
    int count = 0;
    for (GLuint id = 1; id < 4096; ++id) {
      if (glIsTexture(id)) ++count;
    }
    PROCESS_MEMORY_COUNTERS_EX info{};
    info.cb = sizeof(info);
    if (!GetProcessMemoryInfo(GetCurrentProcess(),
                             reinterpret_cast<PROCESS_MEMORY_COUNTERS*>(&info),
                             sizeof(info))) {
      return 3;
    }
    std::cout << i << ',' << count << ',' << info.PrivateUsage << ','
              << info.WorkingSetSize << std::endl;
    surface.MakeCurrent(false);
  }
}
