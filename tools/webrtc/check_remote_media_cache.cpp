#include "remote_media_cache.h"
#include "base/scoped_ref_ptr.h"

#ifdef NDEBUG
#undef NDEBUG
#endif
#include <atomic>
#include <cassert>
#include <functional>
#include <iostream>
#include <string>
#include <thread>
#include <vector>

struct Track {
  explicit Track(int value, std::function<void()> release = {})
      : value(value), release(std::move(release)) {}
  ~Track() { if (release) release(); }
  void AddRef() { ++references; }
  void Release() { if (--references == 0) delete this; }
  std::atomic<int> references{0};
  const int value;
  std::function<void()> release;
};

using Cache = flutter_webrtc_plugin::RemoteMediaCache<
    std::string, libwebrtc::scoped_refptr<Track>>;

int main() {
  Cache cache;
  assert(!cache.Get("missing"));
  std::atomic<int> released{0};
  auto on_release = [&] {
    // A release callback can re-enter the cache without deadlocking.
    cache.Get("track");
    ++released;
  };
  cache.Set("track", new Track(1, on_release));
  auto held = cache.Get("track");
  auto snapshot = cache.Snapshot();
  cache.Set("track", new Track(2, on_release));
  cache.Erase("track");
  assert(released == 1);
  assert(held->value == 1 && snapshot.at("track")->value == 1);
  held = nullptr;
  assert(released == 1);
  snapshot.clear();
  assert(released == 2);

  // Replacement itself must also release outside the lock.
  cache.Set("track", new Track(3, on_release));
  cache.Set("track", new Track(4, on_release));
  assert(released == 3);
  cache.Erase("track");
  assert(released == 4);

  std::atomic<bool> start{false};
  std::vector<std::thread> readers;
  for (int i = 0; i < 4; ++i) {
    readers.emplace_back([&] {
      while (!start.load()) std::this_thread::yield();
      for (int j = 0; j < 50000; ++j) {
        auto track = cache.Get("track");
        if (track) assert(track->value >= 0);
        for (const auto& entry : cache.Snapshot()) {
          assert(entry.second && entry.second->value >= 0);
        }
      }
    });
  }
  start = true;
  for (int i = 0; i < 50000; ++i) {
    cache.Set("track", new Track(i, on_release));
    if (i % 3 == 0) cache.Erase("track");
  }
  for (auto& reader : readers) reader.join();
  cache.Erase("track");
  assert(released == 50004);
  std::cout << "PASS: ownership, reentrant release, 50000 replacements, "
               "200000 concurrent lookups and snapshots\n";
}
