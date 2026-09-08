APP      := Limelight.app
BUNDLE   := dev.nilobarp.limelight
IDENTITY ?= Limelight Dev
BIN      := .build/release/Limelight
DEST     ?= /Applications

.PHONY: all build bundle sign install run clean cert-help

all: bundle

build:
	swift build -c release

bundle: build
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp $(BIN) $(APP)/Contents/MacOS/Limelight
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
