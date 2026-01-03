# Makefile
# Installs Sass into ./bin/sass.
# 1) Try Dart Sass GitHub release for current OS/arch
# 2) If that fails, fallback to npm "sass"
# Use: make sass
# Optional: make clean-sass

SASS_BIN := $(CURDIR)/bin/sass
SASS_DIR := $(CURDIR)/bin
OS := $(shell uname -s)
ARCH := $(shell uname -m)

# Map uname outputs to dart-sass naming
ifeq ($(OS),Darwin)
  DART_OS := macos
else ifeq ($(OS),Linux)
  DART_OS := linux
else ifeq ($(OS),Windows_NT)
  DART_OS := windows
else
  DART_OS := unknown
endif

# Normalize ARCH names to dart-sass naming
# Common cases: x86_64 -> x64, aarch64/arm64 -> arm64
ifeq ($(ARCH),x86_64)
  DART_ARCH := x64
else ifeq ($(ARCH),amd64)
  DART_ARCH := x64
else ifeq ($(ARCH),arm64)
  DART_ARCH := arm64
else ifeq ($(ARCH),aarch64)
  DART_ARCH := arm64
else
  DART_ARCH := unknown
endif

DART_VERSION ?= 1.97.1

# Compose download artifact names
DART_BASE := dart-sass-$(DART_VERSION)-$(DART_OS)-$(DART_ARCH)
DART_TGZ := $(DART_BASE).tar.gz
DART_ZIP := $(DART_BASE).zip
DART_URL := https://github.com/sass/dart-sass/releases/download/$(DART_VERSION)/$(DART_TGZ)
DART_URL_WIN := https://github.com/sass/dart-sass/releases/download/$(DART_VERSION)/$(DART_ZIP)

CURL := curl -fL --retry 3 --retry-delay 2
UNAME_S := $(OS)

.PHONY: sass clean-sass npm-sass ensure-bin test

sass: $(SASS_BIN)
	@echo "Sass ready at $(SASS_BIN)"

test:
	crystal spec


$(SASS_BIN): ensure-bin
	@echo "Attempting Dart Sass install for $(DART_OS)/$(DART_ARCH) version $(DART_VERSION)..."
	@set -e; \
	if [ "$(DART_OS)" = "unknown" ] || [ "$(DART_ARCH)" = "unknown" ]; then \
	  echo "Unknown platform $(OS)/$(ARCH). Falling back to npm sass."; \
	  $(MAKE) -f $(lastword $(MAKEFILE_LIST)) npm-sass; \
	  exit 0; \
	fi; \
	tmpdir=$$(mktemp -d); \
	trap 'rm -rf "$$tmpdir"' EXIT; \
	cd $$tmpdir; \
	if [ "$(UNAME_S)" = "Darwin" ] || [ "$(UNAME_S)" = "Linux" ]; then \
	  echo "Downloading $(DART_URL)"; \
	  if $(CURL) -o $(DART_TGZ) "$(DART_URL)"; then \
		mkdir dart && tar -xzf $(DART_TGZ) -C dart --strip-components=1; \
		mkdir -p "$(SASS_DIR)"; \
		cp -R dart/* "$(SASS_DIR)/"; \
		chmod +x "$(SASS_BIN)"; \
		echo "Installed Dart Sass to $(SASS_BIN)"; \
	  else \
		echo "Dart download failed. Falling back to npm sass..."; \
		$(MAKE) -f $(lastword $(MAKEFILE_LIST)) npm-sass; \
	  fi; \
	elif [ "$(UNAME_S)" = "Windows_NT" ]; then \
	  echo "Downloading $(DART_URL_WIN)"; \
	  if $(CURL) -o $(DART_ZIP) "$(DART_URL_WIN)"; then \
		if ! command -v unzip >/dev/null 2>&1; then \
		  echo "unzip not found. Falling back to npm sass..."; \
		  $(MAKE) -f $(lastword $(MAKEFILE_LIST)) npm-sass; \
		else \
		  mkdir dart && unzip -q $(DART_ZIP) -d dart; \
		  mkdir -p "$(SASS_DIR)"; \
		  if [ -f dart/dart-sass/sass.bat ]; then \
			cp dart/dart-sass/sass.bat "$(SASS_DIR)/sass.bat"; \
			echo "Installed Dart Sass (Windows) to $(SASS_DIR)/sass.bat"; \
		  elif [ -f dart/sass.bat ]; then \
			cp dart/sass.bat "$(SASS_DIR)/sass.bat"; \
			echo "Installed Dart Sass (Windows) to $(SASS_DIR)/sass.bat"; \
		  else \
			echo "Could not locate sass.bat in archive. Falling back to npm sass..."; \
			$(MAKE) -f $(lastword $(MAKEFILE_LIST)) npm-sass; \
		  fi; \
		fi; \
	  else \
		echo "Dart download failed. Falling back to npm sass..."; \
		$(MAKE) -f $(lastword $(MAKEFILE_LIST)) npm-sass; \
	  fi; \
	else \
	  echo "Unsupported OS $(UNAME_S). Falling back to npm sass..."; \
	  $(MAKE) -f $(lastword $(MAKEFILE_LIST)) npm-sass; \
	fi

ensure-bin:
	@mkdir -p "$(SASS_DIR)"

clean-sass:
	@rm -f $(SASS_BIN) $(SASS_DIR)/sass.bat
	@echo "Removed local Sass binaries"