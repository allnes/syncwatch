cmake_minimum_required(VERSION 3.14)
project(surface_probe LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 17)
add_executable(surface_probe probe.cc
  "${MEDIA_KIT_VIDEO_ROOT}/windows/angle_surface_manager.cc"
  "${MEDIA_KIT_VIDEO_ROOT}/windows/utils.cc")
target_compile_definitions(surface_probe PRIVATE UNICODE _UNICODE)
target_include_directories(surface_probe PRIVATE
  "${MEDIA_KIT_VIDEO_ROOT}/windows" "${ANGLE_ROOT}/include")
target_link_libraries(surface_probe PRIVATE
  "${ANGLE_ROOT}/lib/libEGL.dll.lib" "${ANGLE_ROOT}/lib/libGLESv2.dll.lib"
  d3d11 dxgi psapi)
