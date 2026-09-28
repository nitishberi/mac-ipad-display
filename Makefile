.PHONY: build release install uninstall test-syntax clean

PREFIX ?= $(HOME)/.local
BINDIR := $(PREFIX)/bin
SWIFT_BUILD_FLAGS ?= -c release

build:
	swift build $(SWIFT_BUILD_FLAGS)

release: build
	@echo "Binary: $$(swift build $(SWIFT_BUILD_FLAGS) --show-bin-path)/mac-ipad-display"

install: build
	mkdir -p "$(BINDIR)"
	cp "$$(swift build $(SWIFT_BUILD_FLAGS) --show-bin-path)/mac-ipad-display" "$(BINDIR)/mac-ipad-display"
	chmod +x "$(BINDIR)/mac-ipad-display"
	@echo "Installed $(BINDIR)/mac-ipad-display"
	@echo "Next: mac-ipad-display init-config && mac-ipad-display install-agent --menubar"

uninstall:
	"$(BINDIR)/mac-ipad-display" uninstall-agent || true
	rm -f "$(BINDIR)/mac-ipad-display"
	@echo "Removed binary (config/logs left in place). See Scripts/uninstall.sh for full cleanup."

# Syntax-check individual files is not available without macOS SDK; use swift build on a Mac.
clean:
	swift package clean || rm -rf .build

hooks-install:
	./Scripts/install-hooks.sh
