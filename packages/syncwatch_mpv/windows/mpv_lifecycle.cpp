#include <windows.h>
#include <objbase.h>

#include <cstdio>
#include <system_error>
#include <thread>

namespace {
using Destroy = void (*)(void*);

void DestroyInMta(void* handle, const char* entry_point) noexcept {
  // All forwarded APIs and the renderer use this same, unmodified mpv DLL.
  const auto module = GetModuleHandleW(L"libmpv-2.dll");
  const auto destroy = reinterpret_cast<Destroy>(
      module ? GetProcAddress(module, entry_point) : nullptr);
  if (!destroy) {
    std::fprintf(stderr, "SyncWatch: cannot resolve %s in libmpv-2.dll\n",
                 entry_point);
    return;
  }

  try {
    HRESULT status = E_FAIL;
    std::thread worker([&] {
      // media_kit's async device observation creates mpv's monitor in its core
      // MTA, but teardown runs on the caller of mpv_(terminate_)destroy. The bundled
      // mpv unconditionally calls CoUninitialize there. On Flutter's STA this
      // consumes another plugin's COM reference and breaks NetworkListManager.
      // A fresh thread with cookie-based MTA membership has no thread-owned
      // COM reference for that unmatched CoUninitialize to consume. The cookie
      // also keeps MTA objects alive while mpv joins its own core thread.
      CO_MTA_USAGE_COOKIE cookie = nullptr;
      status = CoIncrementMTAUsage(&cookie);
      if (FAILED(status)) return;
      destroy(handle);
      status = CoDecrementMTAUsage(cookie);
    });
    worker.join();
    if (FAILED(status)) {
      std::fprintf(stderr, "SyncWatch: mpv MTA teardown failed (0x%08lx)\n",
                   static_cast<unsigned long>(status));
    }
  } catch (const std::system_error& error) {
    // Never fall back to consuming the caller's COM apartment on a resource
    // allocation failure. Report it rather than corrupting other plugins.
    std::fprintf(stderr, "SyncWatch: cannot start mpv teardown: %s\n",
                 error.what());
  }
}
}  // namespace

extern "C" void mpv_destroy(void* handle) {
  DestroyInMta(handle, "mpv_destroy");
}

extern "C" void mpv_terminate_destroy(void* handle) {
  DestroyInMta(handle, "mpv_terminate_destroy");
}
