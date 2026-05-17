Pod::Spec.new do |s|
  s.name             = 'flutter_incall_manager'
  s.version          = '4.2.1'
  s.summary          = 'Flutter plugin for handling media routes, sensors, and events during audio/video calls.'
  s.description      = <<-DESC
A Flutter plugin that provides in-call management capabilities including audio session management,
proximity sensor monitoring, speakerphone control, and ringtone/ringback playback.
                       DESC
  s.homepage         = 'https://github.com/react-native-webrtc/react-native-incall-manager'
  s.license          = { :type => 'ISC' }
  s.author           = { 'zxcpoiu' => 'zxcpoiu@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*.{h,m,swift}'
  s.public_header_files = 'Classes/**/*.h'
  s.dependency 'Flutter'
  s.platform = :ios, '12.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
