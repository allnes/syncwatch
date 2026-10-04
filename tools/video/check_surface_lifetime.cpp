// Exercises the resolved media_kit_video renderer with the application ANGLE DLLs.
// Keep generated binaries and measurement output outside the checkout.
#include "angle_surface_manager.h"
#include <dxgi1_4.h>
#include <psapi.h>
#include <chrono>
#include <iostream>
#include <memory>
#include <stdexcept>
#include <string>
#include <vector>

using Microsoft::WRL::ComPtr;

void Check(HRESULT hr, const char* name) {
  if (FAILED(hr)) throw std::runtime_error(name);
}

struct Readback {
  ComPtr<ID3D11Device> device;
  ComPtr<ID3D11DeviceContext> context;
  ComPtr<IDXGIAdapter3> adapter;
  Readback() {
    Check(D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, 0,
      nullptr, 0, D3D11_SDK_VERSION, &device, nullptr, &context), "reader device");
    ComPtr<IDXGIDevice> dxgi;
    ComPtr<IDXGIAdapter> base;
    Check(device.As(&dxgi), "DXGI device");
    Check(dxgi->GetAdapter(&base), "DXGI adapter");
    Check(base.As(&adapter), "DXGI adapter3");
  }
  unsigned long long Usage(DXGI_MEMORY_SEGMENT_GROUP segment) {
    DXGI_QUERY_VIDEO_MEMORY_INFO value{};
    Check(adapter->QueryVideoMemoryInfo(0, segment, &value), "GPU memory");
    return value.CurrentUsage;
  }
  bool Verify(ANGLESurfaceManager& surface, int color) {
    surface.Read();
    ComPtr<ID3D11Texture2D> shared;
    Check(device->OpenSharedResource(surface.handle(), __uuidof(ID3D11Texture2D),
      reinterpret_cast<void**>(shared.GetAddressOf())), "open shared texture");
    D3D11_TEXTURE2D_DESC desc{};
    shared->GetDesc(&desc);
    if (desc.Width != surface.width() || desc.Height != surface.height() ||
        desc.Format != DXGI_FORMAT_B8G8R8A8_UNORM) return false;
    desc.Usage = D3D11_USAGE_STAGING;
    desc.BindFlags = 0;
    desc.MiscFlags = 0;
    desc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
    ComPtr<ID3D11Texture2D> staging;
    Check(device->CreateTexture2D(&desc, nullptr, &staging), "staging texture");
    context->CopyResource(staging.Get(), shared.Get());
    D3D11_MAPPED_SUBRESOURCE mapped{};
    Check(context->Map(staging.Get(), 0, D3D11_MAP_READ, 0, &mapped), "map");
    bool valid = true;
    for (UINT y : {0u, desc.Height / 2, desc.Height - 1}) {
      for (UINT x : {0u, desc.Width / 2, desc.Width - 1}) {
        auto pixel = static_cast<unsigned char*>(mapped.pData) + y * mapped.RowPitch + x * 4;
        valid &= pixel[0] == (color == 2 ? 255 : 0) &&
                 pixel[1] == (color == 1 ? 255 : 0) &&
                 pixel[2] == (color == 0 ? 255 : 0) && pixel[3] == 255;
      }
    }
    context->Unmap(staging.Get(), 0);
    return valid;
  }
};

void Sample(Readback& reader, int cycle, int textures, bool valid,
            unsigned error, double drawMs) {
  PROCESS_MEMORY_COUNTERS_EX memory{};
  GetProcessMemoryInfo(GetCurrentProcess(), reinterpret_cast<PROCESS_MEMORY_COUNTERS*>(&memory), sizeof(memory));
  std::cout << "SAMPLE {\"cycle\":" << cycle << ",\"textures\":" << textures
    << ",\"valid\":" << (valid ? "true" : "false") << ",\"glError\":" << error
    << ",\"privateBytes\":" << memory.PrivateUsage << ",\"workingSet\":" << memory.WorkingSetSize
    << ",\"gpuLocal\":" << reader.Usage(DXGI_MEMORY_SEGMENT_GROUP_LOCAL)
    << ",\"gpuNonlocal\":" << reader.Usage(DXGI_MEMORY_SEGMENT_GROUP_NON_LOCAL)
    << ",\"drawMs\":" << drawMs << "}" << std::endl;
}

int main(int argc, char** argv) {
  try {
    const int cycles = argc > 1 ? std::stoi(argv[1]) : 60;
    Readback reader;
    bool valid = true;
    bool bounded = true;
    int initialTextures = -1;
    Sample(reader, -1, 0, true, 0, 0);
    {
      ANGLESurfaceManager surface(1, 1);
      surface.MakeCurrent(true);
      std::cout << "RENDERER " << glGetString(GL_RENDERER) << std::endl;
      surface.MakeCurrent(false);
      auto preview = std::make_unique<ANGLESurfaceManager>(640, 480);
      for (int cycle = 0; cycle <= cycles; ++cycle) {
        const int width = cycle % 2 == 0 ? 3840 : 1920;
        const int height = cycle % 2 == 0 ? 2160 : 1080;
        surface.SetSize(width, height);
        const auto start = std::chrono::steady_clock::now();
        surface.Draw([&] {
          glViewport(0, 0, width, height);
          glClearColor(cycle % 3 == 0 ? 1.f : 0.f, cycle % 3 == 1 ? 1.f : 0.f,
            cycle % 3 == 2 ? 1.f : 0.f, 1.f);
          glClear(GL_COLOR_BUFFER_BIT);
        });
        const double drawMs = std::chrono::duration<double, std::milli>(
          std::chrono::steady_clock::now() - start).count();
        preview->Draw([] {
          glViewport(0, 0, 640, 480);
          glClearColor(0.f, 1.f, 0.f, 1.f);
          glClear(GL_COLOR_BUFFER_BIT);
        });
        valid &= reader.Verify(*preview, 1);
        valid &= reader.Verify(surface, cycle % 3);
        surface.MakeCurrent(true);
        int textures = 0;
        for (GLuint name = 1; name < 4096; ++name) textures += glIsTexture(name) == GL_TRUE;
        if (initialTextures < 0) initialTextures = textures;
        bounded &= textures <= initialTextures + 1;
        const auto error = glGetError();
        surface.MakeCurrent(false);
        Sample(reader, cycle, textures, valid, error, drawMs);
        if (!valid || error != GL_NO_ERROR) return 2;
      }
    }
    reader.context->ClearState();
    reader.context->Flush();
    Sample(reader, cycles + 1, 0, valid, 0, 0);
    if (!bounded) {
      std::cerr << "Resizes retained GL texture objects until context destruction" << std::endl;
      return 7;
    }
    return valid ? 0 : 2;
  } catch (const std::exception& error) {
    std::cerr << error.what() << std::endl;
    return 1;
  }
}
