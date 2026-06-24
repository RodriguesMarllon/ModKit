PROJECT  := ModKit.xcodeproj
SCHEME   := ModKit
BUILD_DIR := $(HOME)/Library/Developer/Xcode/DerivedData/ModKit-build
INSTALL_DIR := $(HOME)/Applications

.PHONY: build install run clean

## Build release binary into DerivedData
build:
	xcodebuild -project $(PROJECT) \
	           -scheme $(SCHEME) \
	           -configuration Release \
	           -derivedDataPath $(BUILD_DIR) \
	           build | xcpretty 2>/dev/null || xcodebuild -project $(PROJECT) \
	           -scheme $(SCHEME) \
	           -configuration Release \
	           -derivedDataPath $(BUILD_DIR) \
	           build

## Build + copy .app to ~/Applications (creates dir if needed)
install: build
	pkill -x ModKit || true
	sleep 0.5
	mkdir -p $(INSTALL_DIR)
	rm -rf $(INSTALL_DIR)/ModKit.app
	cp -R $(BUILD_DIR)/Build/Products/Release/ModKit.app $(INSTALL_DIR)/ModKit.app
	touch $(INSTALL_DIR)/ModKit.app
	/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -f $(INSTALL_DIR)/ModKit.app
	@echo "✓ Installed to $(INSTALL_DIR)/ModKit.app"

## Build, install and launch
run: install
	open $(INSTALL_DIR)/ModKit.app

## Remove DerivedData and installed app
clean:
	rm -rf $(BUILD_DIR)
	rm -rf $(INSTALL_DIR)/ModKit.app
	@echo "✓ Cleaned"
