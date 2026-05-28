APP     := Safari Swipe
SCHEME  := Safari Swipe
PROJECT := SafariSwipe/SafariSwipe.xcodeproj

BUILD   := build
PRODUCT := $(BUILD)/Build/Products/Release/$(APP).app
DEST    := $(HOME)/Applications/$(APP).app

.PHONY: all generate icons build install uninstall run clean help

all: build

# Regenerate the Xcode project from extension source files
generate:
	python3 generate_project.py

# Regenerate bookmark icon PNGs
icons:
	cd extension && python3 create_icons.py

# Auto-generate the project if it doesn't exist yet
$(PROJECT):
	python3 generate_project.py

# Build the app in Release mode (requires Xcode)
build: $(PROJECT)
	xcodebuild \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-configuration Release \
		-derivedDataPath "$(BUILD)" \
		-quiet

# Build and copy to ~/Applications
install: build
	mkdir -p "$(HOME)/Applications"
	rm -rf "$(DEST)"
	cp -r "$(PRODUCT)" "$(DEST)"
	@echo "Installed → $(DEST)"
	@echo ""
	@echo "Next steps:"
	@echo "  1. make run"
	@echo "  2. Safari → Settings → Advanced → enable 'Show features for web developers'"
	@echo "  3. Safari → Develop → Allow Unsigned Extensions  (required after every Safari restart)"
	@echo "  4. Safari → Settings → Extensions → enable Safari Swipe"

# Remove the installed app
uninstall:
	rm -rf "$(DEST)"
	@echo "Uninstalled $(APP)"

# Open the installed app
run:
	open "$(DEST)"
	@echo "Now: Safari → Develop → Allow Unsigned Extensions, then Settings → Extensions → Safari Swipe"

# Remove build artifacts
clean:
	rm -rf "$(BUILD)"

help:
	@echo "Targets:"
	@echo "  make build      Build the app (requires Xcode)"
	@echo "  make install    Build and install to ~/Applications"
	@echo "  make uninstall  Remove from ~/Applications"
	@echo "  make run        Open the installed app"
	@echo "  make generate   Regenerate Xcode project from extension sources"
	@echo "  make icons      Regenerate icon PNGs"
	@echo "  make clean      Remove build artifacts (.build/)"
