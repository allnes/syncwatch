cmake_minimum_required(VERSION 3.14)
project(syncwatch_mpv LANGUAGES CXX)

add_library(syncwatch_mpv SHARED mpv_lifecycle.cpp mpv_exports.def)
target_compile_features(syncwatch_mpv PRIVATE cxx_std_17)
target_compile_definitions(syncwatch_mpv PRIVATE _WIN32_WINNT=0x0602)
if(NOT MEDIA_KIT_LIBS_AVAILABLE)
  message(FATAL_ERROR "syncwatch_mpv requires media_kit_libs_windows_video")
endif()
# Resolve forwarder symbols against the same import library as media_kit_video.
target_link_libraries(syncwatch_mpv PRIVATE ole32
  "${CMAKE_BINARY_DIR}/libmpv/libmpv.dll.a")
set(syncwatch_mpv_bundled_libraries "$<TARGET_FILE:syncwatch_mpv>" PARENT_SCOPE)
