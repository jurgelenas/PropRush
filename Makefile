SHELL := /bin/bash
SRC_DIR := src

STYLUA_VERSION := 2.3.1
STYLUA := bin/stylua
STYLUA_URL := https://github.com/JohnnyMorganz/StyLua/releases/download/v$(STYLUA_VERSION)/stylua-linux-x86_64.zip

LUALS_VERSION := 3.17.1
LUALS_DIR := bin/lua-language-server
LUALS := $(LUALS_DIR)/bin/lua-language-server
LUALS_URL := https://github.com/LuaLS/lua-language-server/releases/download/$(LUALS_VERSION)/lua-language-server-$(LUALS_VERSION)-linux-x64.tar.gz

LUAC_VERSION := 1.0.0
LUAC_DIR := bin/edgetx-luac
LUAC := $(LUAC_DIR)/edgetx-luac
LUAC_URL := https://github.com/EdgeTX/edgetx-luac-action/releases/download/v$(LUAC_VERSION)/edgetx-luac-v$(LUAC_VERSION)-linux-x64.tar.gz

TOOL := SCRIPTS/TOOLS/PropRush
DIST_DIR := dist
STAGE_DIR := $(DIST_DIR)/sdcard
VERSION ?= $(or $(shell git rev-parse HEAD 2>/dev/null | cut -c1-7),dev)
ZIP_NAME ?= proprush-$(VERSION)

.PHONY: help install-tools install-stylua install-luals install-luac format format-check typecheck check test test-host build \
	sync push

help:
	@echo "Usage: make <target>"
	@echo ""
	@echo "  install-tools   Install stylua, lua-language-server and edgetx-luac"
	@echo "  format          Format Lua files with stylua"
	@echo "  format-check    Check formatting without modifying files"
	@echo "  typecheck       Run lua-language-server type checking"
	@echo "  check           Run format-check and typecheck"
	@echo "  test            Run the specs in the EdgeTX simulator (SPEC=name runs some)"
	@echo "  test-host       Run the specs on the host lua5.3"
	@echo "  build           Build the release zip in dist/ (VERSION=.. ZIP_NAME=..)"
	@echo "  sync            Sync source files to EdgeTX simulator SD card"
	@echo "  push            Install package to EdgeTX radio as bytecode and eject"

install-stylua:
	mkdir -p bin
	curl -fSL -o bin/stylua.zip $(STYLUA_URL)
	unzip -o -q bin/stylua.zip -d bin
	rm bin/stylua.zip
	chmod +x $(STYLUA)

install-luals:
	mkdir -p $(LUALS_DIR)
	curl -fSL $(LUALS_URL) | tar xz -C $(LUALS_DIR)

install-luac:
	mkdir -p $(LUAC_DIR)
	curl -fSL $(LUAC_URL) | tar xz -C $(LUAC_DIR)

install-tools: install-stylua install-luals install-luac

format:
	$(STYLUA) $(SRC_DIR)

format-check:
	$(STYLUA) --check $(SRC_DIR)

typecheck:
	$(LUALS) --check . --logpath=/tmp/proprush-luals

check: format-check typecheck

SIM := edgetx-cli dev simulator --radios-dir ../edgetx-firmware/radios --radio "RadioMaster Boxer" --headless \
	--sdcard /tmp/proprush-test-sd --timeout 120s

test:
	@mkdir -p /tmp/proprush-test-sd
	@$(SIM) --script test/run.lua 2>&1 | grep -v -E '^[0-9]+ms: |^-[EW]- |^  [ℹ✓⏳] ' ; exit $${PIPESTATUS[0]}

test-host:
	lua5.3 test/run.lua

build:
	rm -rf $(DIST_DIR)
	mkdir -p $(STAGE_DIR)/$(TOOL)
	cp -r $(SRC_DIR)/$(TOOL)/. $(STAGE_DIR)/$(TOOL)/
	find $(STAGE_DIR) -name '*.luac' -delete
	find $(STAGE_DIR) -name '*.txt' -delete
	printf 'return "%s"\n' '$(VERSION)' > $(STAGE_DIR)/$(TOOL)/version.lua
	find $(STAGE_DIR) -name '*.lua' | while read -r f; do $(LUAC) -s -o "$${f}c" "$$f" || exit 1; done
	cd $(STAGE_DIR) && zip -q -r ../$(ZIP_NAME).zip SCRIPTS
	@echo "Built $(DIST_DIR)/$(ZIP_NAME).zip (version $(VERSION))"

sync:
	edgetx-cli dev sync ../edgetx-sdcard

push:
	edgetx-cli pkg install . --pre-compile --eject
