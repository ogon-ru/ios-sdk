Pod::Spec.new do |spec|
  spec.name         = "OgonWidgetSDK"
  spec.version      = "0.0.1"
  spec.summary      = "Ogon widget integration lib"
  spec.homepage     = "https://ogon.ru"
  spec.license      = "MIT" # TODO
  # spec.license      = { :type => "MIT", :file => "FILE_LICENSE" }
  spec.author       = "Set Partnerstv"
  spec.platform     = :ios, "11.0"
  spec.source       = { :git => "https://git.setpartnerstv.ru/frontend/ios-sdk.git", :tag => "#{spec.version}" } # TODO
  spec.source_files = "sdk/**/*.{swift,h}"
  spec.public_header_files = "sdk/**/*.h"
  spec.requires_arc = true
  spec.swift_version = "5.0"
  spec.dependency "SwiftProtobuf", "~> 1.14.0"
end
