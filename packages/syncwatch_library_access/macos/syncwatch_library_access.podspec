Pod::Spec.new do |s|
  s.name = 'syncwatch_library_access'
  s.version = '0.1.0'
  s.summary = 'Persistent read access to the selected SyncWatch library.'
  s.homepage = 'https://github.com/allnes/syncwatch'
  s.author = 'SyncWatch contributors'
  s.license = { :type => 'Apache-2.0', :file => '../../../LICENSE' }
  s.source = { :path => '.' }
  s.source_files = 'syncwatch_library_access/Sources/syncwatch_library_access/**/*.swift'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '10.15'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
