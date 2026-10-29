SHELL := /bin/bash
SRC_DIR := src

STYLUA_VERSION := 2.3.1
STYLUA := bin/stylua
STYLUA_URL := https://github.com/JohnnyMorganz/StyLua/releases/download/v$(STYLUA_VERSION)/stylua-linux-x86_64.zip

LUALS_VERSION := 3.17.1
LUALS_DIR := bin/lua-language-server
LUALS := $(LUALS_DIR)/bin/lua-language-server
LUALS_URL := https://github.com/LuaLS/lua-language-server/releases/download/$(LUALS_VERSION)/lua-language-server-$(LUALS_VERSION)-linux-x64.tar.gz

.PHONY: help install-tools install-stylua install-luals format format-check typecheck check test sync push

help:
	@echo "Usage: make <target>"
	@echo ""
	@echo "  install-tools   Install stylua and lua-language-server"
	@echo "  format          Format Lua files with stylua"
	@echo "  format-check    Check formatting without modifying files"
	@echo "  typecheck       Run lua-language-server type checking"
	@echo "  check           Run format-check and typecheck"
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

install-tools: install-stylua install-luals

format:
	$(STYLUA) $(SRC_DIR)

format-check:
	$(STYLUA) --check $(SRC_DIR)

typecheck:
	$(LUALS) --check . --logpath=/tmp/fpv-sim-luals

check: format-check typecheck

SIM := edgetx-cli dev simulator --radios-dir ../edgetx-firmware/radios --radio "RadioMaster Boxer" --headless \
	--sdcard /tmp/fpv-sim-test-sd --timeout 120s

test:
	@mkdir -p /tmp/fpv-sim-test-sd
	@$(SIM) --script test/run.lua 2>&1 | grep -v -E '^[0-9]+ms: |^-[EW]- |^  [ℹ✓⏳] ' ; exit $${PIPESTATUS[0]}

sync:
	edgetx-cli dev sync ../edgetx-sdcard

push:
	edgetx-cli pkg install . --pre-compile --eject
