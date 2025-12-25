Pod::Spec.new do |s|
  s.name             = 'v2ray_dan'
  s.version          = '0.0.1'
  s.summary          = 'Custom V2Ray implementation for Flutter (macOS)'
  s.description      = <<-DESC
Custom V2Ray implementation for Flutter (macOS)
                       DESC
  s.homepage         = 'https://danials.org'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Danial' => 'danial@danials.org' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.resources        = 'Resources/**/*'
  s.dependency 'FlutterMacOS'

  s.platform = :osx, '10.11'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
