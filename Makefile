# -----------------------------
# Config
# -----------------------------
# List of recordings to build; each must have ./docs/<name>.sh
NAMES            ?= build deploy td-build td-deploy

TITLE_build     ?= Building the Java CLI Env Reader Application
TITLE_deploy    ?= Deploying the Java CLI Env Reader Application
TITLE_td-build  ?= Transform the native Java CLI Env Reader into a confidential Application
TITLE_td-deploy ?= Deploying the Confidential Java CLI Env Reader Application

# Recording parameters
TYPE_SPEED       ?= 24
PAUSE_AFTER_CMD  ?= 0.6
COLS             ?= 100

# Optional per-name titles:
# e.g. TITLE_demo="Building the Java CLI Env Reader Application"
#      TITLE_deploy="Deploying the Java CLI Env Reader Application"

DEPS := asciinema svg-term

RED    := \033[0;31m
GREEN  := \033[0;32m
YELLOW := \033[1;33m
RESET  := \033[0m

# -----------------------------
# Derived file lists
# -----------------------------
SCRIPTS := $(addprefix docs/,$(addsuffix .sh,$(NAMES)))
CASTS   := $(addprefix docs/,$(addsuffix .cast,$(NAMES)))
SVGS    := $(addprefix docs/,$(addsuffix .svg,$(NAMES)))

# Helper to resolve title: if TITLE_<name> is set use it, else default to the name
title = $(if $(value TITLE_$1),$(value TITLE_$1),$1)

.PHONY: all record svg check-deps clean help
all: record svg

# -----------------------------
# Pattern rules
# -----------------------------
# Record: docs/<name>.cast from docs/<name>.sh
docs/%.cast: docs/%.sh | check-deps
	@echo "$(YELLOW)Recording to $@…$(RESET)"
	@TYPE_SPEED=$(TYPE_SPEED) PAUSE_AFTER_CMD=$(PAUSE_AFTER_CMD) \
	asciinema rec --overwrite -q -t "$(call title,$*)" -c "$<" "$@"
	@echo "$(GREEN)✓ Recorded: $@$(RESET)"

# Render SVG: docs/<name>.svg from docs/<name>.cast
docs/%.svg: docs/%.cast | check-deps
	@echo "$(YELLOW)Exporting SVG to $@…$(RESET)"
	@cat "$<" | svg-term --out "$@" --window --no-cursor --width $(COLS)
	@echo "$(GREEN)✓ SVG created: $@$(RESET)"

# -----------------------------
# Front-door targets
# -----------------------------
record: $(CASTS)
svg:    $(SVGS)

# -----------------------------
# Dependency checks
# -----------------------------
check-deps:
	@missing=""
	@for cmd in $(DEPS); do command -v $$cmd >/dev/null 2>&1 || missing="$$missing $$cmd"; done; \
	if [ -n "$$missing" ]; then \
	  echo "$(RED)Missing tools:$$missing$(RESET)\n"; \
	  echo "Install:"; \
	  echo "  asciinema : (Linux) your pkg mgr | (macOS) brew install asciinema | (PyPI 2.x) pipx install asciinema"; \
	  echo "  svg-term  : npm install -g svg-term-cli"; \
	  exit 1; \
	else \
	  echo "$(GREEN)All dependencies available: $(DEPS)$(RESET)"; \
	fi

# -----------------------------
# Utilities
# -----------------------------
clean:
	@rm -f $(CASTS) $(SVGS)
	@echo "$(GREEN)Cleaned$(RESET)"

help:
	@echo "Usage:"
	@echo "  make NAMES=\"demo deploy\"              # build casts + svgs for listed names"
	@echo "  make record | make svg | make all       # scoped targets"
	@echo "Options:"
	@echo "  TYPE_SPEED=$(TYPE_SPEED)  PAUSE_AFTER_CMD=$(PAUSE_AFTER_CMD)  COLS=$(COLS)"
	@echo "Per-name titles:"
	@echo "  make NAMES=\"demo\" TITLE_demo=\"Building the Java CLI Env Reader Application\""
