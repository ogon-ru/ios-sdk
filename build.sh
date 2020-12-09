#!/bin/sh

# create folder where we place built frameworks
rm -rf build
mkdir build
# build framework for simulators
xcodebuild clean build \
  -workspace sdk.xcworkspace \
  -scheme sdk \
  -configuration Release \
  -sdk iphonesimulator \
  -derivedDataPath derived_data \
  EXCLUDED_ARCHS="arm64" \
  BITCODE_GENERATION_MODE="bitcode"
# create folder to store compiled framework for simulator
mkdir build/simulator
# copy compiled framework for simulator into our build folder
cp -r derived_data/Build/Products/Release-iphonesimulator/sdk.framework build/simulator
#build framework for devices
xcodebuild clean build \
  -workspace sdk.xcworkspace \
  -scheme sdk \
  -configuration Release \
  -sdk iphoneos \
  -derivedDataPath derived_data \
  BITCODE_GENERATION_MODE="bitcode"
# create folder to store compiled framework for simulator
mkdir build/devices
# copy compiled framework for simulator into our build folder
cp -r derived_data/Build/Products/Release-iphoneos/sdk.framework build/devices
# create folder to store compiled universal framework
mkdir build/universal
####################### Create universal framework #############################
# copy device framework into universal folder
cp -r build/devices/sdk.framework build/universal/
# create framework binary compatible with simulators and devices, and replace binary in unviersal framework
lipo -create \
  build/simulator/sdk.framework/sdk \
  build/devices/sdk.framework/sdk \
  -output build/universal/sdk.framework/sdk
# copy simulator Swift public interface to universal framework
cp -R build/simulator/sdk.framework/Modules/sdk.swiftmodule/* build/universal/sdk.framework/Modules/sdk.swiftmodule
