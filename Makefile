DEVELOPER_DIR = /Applications/Xcode.app/Contents/Developer
export DEVELOPER_DIR

.PHONY: build test lint app run
build:
	swift build
test:
	swift test
lint:
	SOURCEKIT_TOOLCHAIN_PATH="$(DEVELOPER_DIR)/Toolchains/XcodeDefault.xctoolchain" swiftlint lint --strict
app:
	bash scripts/bundle.sh
run: app
	open dist/Spare.app
