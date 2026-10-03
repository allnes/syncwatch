#include <windows.h>
#include <netlistmgr.h>
#include <client.h>

#include <cstdio>
#include <filesystem>
#include <fstream>
#include <string>

// Use the asynchronous API, as media_kit does for audio-device-list. The
// synchronous getter can initialize WASAPI on the caller instead of the core.
bool ReadDevices(mpv_handle* player,
                 decltype(&mpv_get_property_async) get,
                 decltype(&mpv_wait_event) wait) {
  constexpr uint64_t request = 123;
  if (get(player, request, "audio-device-list", MPV_FORMAT_NODE) < 0) return false;
  const auto deadline = GetTickCount64() + 10000;
  while (GetTickCount64() < deadline) {
    const auto event = wait(player, 0.1);
    if (event->event_id != MPV_EVENT_GET_PROPERTY_REPLY ||
        event->reply_userdata != request) continue;
    if (event->error < 0 || !event->data) return false;
    const auto property = static_cast<mpv_event_property*>(event->data);
    return property->format == MPV_FORMAT_NODE && property->data;
  }
  return false;
}

int wmain(int argc, wchar_t** argv) {
  if (argc != 5) return 2;
  // DLL search changes are confined to this standalone regression process.
  SetDllDirectoryW(argv[1]);
  const bool baseline = std::wstring(argv[2]) == L"baseline";
  const std::wstring apartment = argv[3];
  const bool initialize_com = apartment != L"none";
  if (initialize_com) {
    const auto flags = apartment == L"sta" ? COINIT_APARTMENTTHREADED
                                           : COINIT_MULTITHREADED;
    if (FAILED(CoInitializeEx(nullptr, flags))) return 3;
    if (FAILED(CoInitializeEx(nullptr, flags))) return 3;
  }
  APTTYPE before_type = APTTYPE_CURRENT;
  APTTYPEQUALIFIER before_qualifier = APTTYPEQUALIFIER_NONE;
  CoGetApartmentType(&before_type, &before_qualifier);

  INetworkListManager* manager = nullptr;
  if (initialize_com && FAILED(CoCreateInstance(
          CLSID_NetworkListManager, nullptr, CLSCTX_ALL,
          IID_PPV_ARGS(&manager)))) return 4;

  const auto original = LoadLibraryW(L"libmpv-2.dll");
  const auto library = baseline ? original : LoadLibraryW(L"syncwatch_mpv.dll");
  if (!original || !library) {
    std::fprintf(stderr, "Cannot load mpv libraries: %lu\n", GetLastError());
    return 5;
  }
  if (!baseline) {
    std::ifstream exports{std::filesystem::path(argv[4])};
    if (!exports) return 6;
    int count = 0;
    std::string line;
    while (std::getline(exports, line)) {
      const auto start = line.find("mpv_");
      if (start == std::string::npos) continue;
      const auto end = line.find_first_of("= \r\n", start);
      const auto name = line.substr(start, end - start);
      const auto source = GetProcAddress(original, name.c_str());
      const auto target = GetProcAddress(library, name.c_str());
      const bool teardown = name == "mpv_destroy" || name == "mpv_terminate_destroy";
      if (!source || !target || (!teardown && source != target)) {
        std::fprintf(stderr, "Export mismatch: %s\n", name.c_str());
        return 6;
      }
      ++count;
    }
    if (count < 40) return 6;
    std::printf("Verified %d mpv exports\n", count);
  }

  const auto create = reinterpret_cast<decltype(&mpv_create)>(GetProcAddress(library, "mpv_create"));
  const auto initialize = reinterpret_cast<decltype(&mpv_initialize)>(GetProcAddress(library, "mpv_initialize"));
  const auto get = reinterpret_cast<decltype(&mpv_get_property_async)>(GetProcAddress(library, "mpv_get_property_async"));
  const auto wait = reinterpret_cast<decltype(&mpv_wait_event)>(GetProcAddress(library, "mpv_wait_event"));
  const auto create_client = reinterpret_cast<decltype(&mpv_create_client)>(GetProcAddress(library, "mpv_create_client"));
  const auto destroy = reinterpret_cast<decltype(&mpv_destroy)>(GetProcAddress(library, "mpv_destroy"));
  const auto terminate = reinterpret_cast<decltype(&mpv_terminate_destroy)>(GetProcAddress(library, "mpv_terminate_destroy"));
  if (!create || !initialize || !get || !wait || !create_client || !destroy || !terminate) return 6;

  for (int cycle = 0; cycle < 12; ++cycle) {
    const auto player = create();
    if (!player || initialize(player) < 0) return 8;
    // Audio-device-list creates mpv's WASAPI hotplug monitor on its core MTA.
    if (!ReadDevices(player, get, wait)) return 9;
    const auto secondary = create_client(player, "lifecycle-test");
    if (!secondary) return 10;
    destroy(secondary);
    // Destroying a secondary must leave the core alive.
    if (!ReadDevices(player, get, wait)) return 11;
    (cycle % 2 ? destroy : terminate)(player);

    APTTYPE type = APTTYPE_CURRENT;
    APTTYPEQUALIFIER qualifier = APTTYPEQUALIFIER_NONE;
    const auto com = CoGetApartmentType(&type, &qualifier);
    std::printf("cycle=%d apartmentHr=%08lx apartment=%d qualifier=%d\n",
                cycle, com, static_cast<int>(type), static_cast<int>(qualifier));
    std::fflush(stdout);
    if (initialize_com && (FAILED(com) || type != before_type || qualifier != before_qualifier)) {
      // The baseline has invalidated its COM proxies; do not dereference them.
      return 7;
    }
    if (!initialize_com && SUCCEEDED(com) &&
        !(type == APTTYPE_MTA && qualifier == APTTYPEQUALIFIER_IMPLICIT_MTA)) return 7;
    if (manager) {
      IEnumNetworkConnections* connections = nullptr;
      const auto hr = manager->GetNetworkConnections(&connections);
      std::printf("networkHr=%08lx\n", hr);
      if (FAILED(hr)) return 12;
      connections->Release();
    }
  }
  if (manager) manager->Release();
  if (initialize_com) {
    CoUninitialize();
    CoUninitialize();
  }
  return 0;
}
