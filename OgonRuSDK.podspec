Pod::Spec.new do |spec|
  spec.name         = "OgonRuSDK"
  spec.version      = "1.0.3"
  spec.summary      = "Ogon widget integration lib"
  spec.homepage     = "https://github.com/ogon-ru/ios-sdk"
  spec.license      = { :type => "MIT", :file => "LICENSE" }
  spec.author       = "Egor Komarov"
  spec.platform     = :ios, "11.0"
  spec.source       = { :git => "https://github.com/ogon-ru/ios-sdk.git", :tag => "#{spec.version}" }
  spec.source_files = "sdk/**/*.{swift,h,m}"
  spec.requires_arc = true
  spec.swift_version = "5.0"
  spec.dependency "SwiftProtobuf", "~> 1.14.0"
  spec.frameworks = ["UIKit", "WebKit"]
end
