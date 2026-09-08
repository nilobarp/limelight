APP      := Limelight.app
BUNDLE   := dev.nilobarp.limelight
IDENTITY ?= Limelight Dev
BIN      := .build/release/Limelight
ICON     := Resources/AppIcon.icns
DEST     ?= /Applications

.PHONY: all build bundle sign install run icon clean cert-help

all: bundle

build:
	swift build -c release

# Drawn with CoreGraphics from the same primitives as Resources/icon.svg, so
# every size is rendered rather than scaled from one bitmap.
icon: $(ICON)

$(ICON): Tools/IconGen.swift Resources/icon.svg
	@mkdir -p .build
	swiftc -O Tools/IconGen.swift -o .build/icongen
	.build/icongen .build/AppIcon.iconset
	iconutil -c icns .build/AppIcon.iconset -o $@

bundle: build $(ICON)
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp $(BIN) $(APP)/Contents/MacOS/Limelight
	cp $(ICON) $(APP)/Contents/Resources/AppIcon.icns
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	$(MAKE) sign

# A stable signing identity is what keeps the Accessibility grant alive across
# rebuilds. Ad-hoc works but changes hash every build, so macOS drops the grant.
# A stable signing identity is what keeps the Accessibility grant alive across
# rebuilds: TCC pins an ad-hoc app's grant to its code hash, which changes every
# build. Resolve the name to a SHA-1 first — several certs can share a common
# name, and codesign refuses an ambiguous match.
sign:
	@hash=$$(security find-identity -v -p codesigning | grep "$(IDENTITY)" | head -1 | awk '{print $$2}'); \
	if [ -n "$$hash" ]; then \
		echo "signing with '$(IDENTITY)' ($$hash)"; \
		codesign --force --deep --sign "$$hash" $(APP); \
	else \
		echo "!! identity '$(IDENTITY)' not found — falling back to ad-hoc."; \
		echo "!! You will have to re-grant Accessibility after every build."; \
		echo "!! Run 'make cert-help' to fix this once."; \
		codesign --force --deep --sign - $(APP); \
	fi

install: bundle
	rm -rf $(DEST)/$(APP)
	cp -R $(APP) $(DEST)/
	@echo "installed to $(DEST)/$(APP)"

run: install
	open $(DEST)/$(APP)

clean:
	rm -rf .build $(APP)

cert-help:
	@echo "Create the stable signing identity once:"
	@echo "  1. Open Keychain Access"
	@echo "  2. Menu: Keychain Access > Certificate Assistant > Create a Certificate…"
	@echo "  3. Name: $(IDENTITY)"
	@echo "     Identity Type: Self Signed Root"
	@echo "     Certificate Type: Code Signing"
	@echo "  4. Create, then re-run 'make install'"
