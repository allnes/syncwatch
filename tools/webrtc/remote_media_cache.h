#ifndef SYNCWATCH_REMOTE_MEDIA_CACHE_H_
#define SYNCWATCH_REMOTE_MEDIA_CACHE_H_

#include <map>
#include <mutex>
#include <utility>

namespace flutter_webrtc_plugin {

// Copy owning references while the signaling thread cannot replace them.
// Never run a media object's destructor or native methods under this mutex:
// those may wait for the signaling thread that also updates this cache.
template <typename Key, typename Reference>
class RemoteMediaCache {
 public:
  Reference Get(const Key& key) const {
    std::lock_guard<std::mutex> lock(mutex_);
    auto it = values_.find(key);
    return it == values_.end() ? Reference{} : it->second;
  }

  void Set(const Key& key, Reference value) {
    std::lock_guard<std::mutex> lock(mutex_);
    using std::swap;
    swap(values_[key], value);
    // The parameter releases the old reference after the lock is destroyed.
  }

  void Erase(const Key& key) {
    Reference removed;
    {
      std::lock_guard<std::mutex> lock(mutex_);
      auto it = values_.find(key);
      if (it == values_.end()) return;
      using std::swap;
      swap(removed, it->second);
      values_.erase(it);
    }
  }

  std::map<Key, Reference> Snapshot() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return values_;
  }

 private:
  mutable std::mutex mutex_;
  std::map<Key, Reference> values_;
};

}  // namespace flutter_webrtc_plugin

#endif  // SYNCWATCH_REMOTE_MEDIA_CACHE_H_
