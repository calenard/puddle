.PHONY: default build install uninstall

BIN := $(notdir $(CURDIR))
# Must match "name" in extension.json (slash command/logical extension name).
EXT := mcp
PUDDLE_HOME ?= $(shell \
	if [ -n "$$XDG_STATE_HOME" ]; then \
		printf '%s/puddle' "$$XDG_STATE_HOME"; \
	elif [ "$$(uname -s)" = "Darwin" ]; then \
		printf '%s/Library/Application Support/puddle' "$$HOME"; \
	else \
		printf '%s/.local/state/puddle' "$$HOME"; \
	fi)

default: install

build:
	go build -o $(BIN) .

install:
	-puddle ext remove $(EXT) --yes
	rm -rf "$(PUDDLE_HOME)/extensions/$(BIN)"
	mkdir -p "$(PUDDLE_HOME)/extensions/$(EXT)"
	cp extension.json "$(PUDDLE_HOME)/extensions/$(EXT)/extension.json"
	go build -o "$(PUDDLE_HOME)/extensions/$(EXT)/$(BIN)" .

uninstall:
	-puddle ext remove $(EXT) --yes
