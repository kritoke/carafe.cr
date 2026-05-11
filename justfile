# Justfile for carafe.cr
# Run tasks: just <recipe>
# List recipes: just --list

# Project root
root := justfile_directory()

# Directories
bin_dir := root / "bin"
sass_bin := bin_dir / "sass"

# Dart Sass version
dart_version := "1.97.1"

# OS detection (mapped to dart-sass naming)
dart_os := if os() == "macos" { "macos" } \
           else if os() == "linux" { "linux" } \
           else if os() == "windows" { "windows" } \
           else { "unknown" }

# Architecture detection (mapped to dart-sass naming)
dart_arch := if arch() == "x86_64" { "x64" } \
             else if arch() == "amd64" { "x64" } \
             else if arch() == "arm64" { "arm64" } \
             else if arch() == "aarch64" { "arm64" } \
             else { "unknown" }

# Download URLs
dart_base := "dart-sass-" + dart_version + "-" + dart_os + "-" + dart_arch
dart_tgz := dart_base + ".tar.gz"
dart_zip := dart_base + ".zip"
dart_url := "https://github.com/sass/dart-sass/releases/download/" + dart_version + "/" + dart_tgz
dart_url_win := "https://github.com/sass/dart-sass/releases/download/" + dart_version + "/" + dart_zip

# Default recipe - list available commands
default:
    @just --list

# Install all dependencies (sass, shards)
install: sass
    shards install

# Install Dart Sass binary
sass: ensure-bin
    #!/usr/bin/env bash
    set -euo pipefail
    
    if [ -f "{{ sass_bin }}" ]; then
        echo "Sass already installed at {{ sass_bin }}"
        {{ sass_bin }} --version
        exit 0
    fi
    
    echo "Attempting Dart Sass install for {{ dart_os }}/{{ dart_arch }} version {{ dart_version }}..."
    
    if [ "{{ dart_os }}" = "unknown" ] || [ "{{ dart_arch }}" = "unknown" ]; then
        echo "Unknown platform {{ dart_os }}/{{ dart_arch }}. Falling back to npm sass."
        just npm-sass
        exit 0
    fi
    
    tmpdir=$(mktemp -d)
    trap 'rm -rf "$tmpdir"' EXIT
    cd "$tmpdir"
    
    if [ "{{ os() }}" = "macos" ] || [ "{{ os() }}" = "linux" ]; then
        echo "Downloading {{ dart_url }}"
        if curl -fL --retry 3 --retry-delay 2 -o {{ dart_tgz }} "{{ dart_url }}"; then
            mkdir dart && tar -xzf {{ dart_tgz }} -C dart --strip-components=1
            mkdir -p "{{ bin_dir }}"
            cp -R dart/* "{{ bin_dir }}/"
            chmod +x "{{ sass_bin }}"
            echo "Installed Dart Sass to {{ sass_bin }}"
        else
            echo "Dart download failed. Falling back to npm sass..."
            just npm-sass
        fi
    elif [ "{{ os() }}" = "windows" ]; then
        echo "Downloading {{ dart_url_win }}"
        if curl -fL --retry 3 --retry-delay 2 -o {{ dart_zip }} "{{ dart_url_win }}"; then
            if ! command -v unzip >/dev/null 2>&1; then
                echo "unzip not found. Falling back to npm sass..."
                just npm-sass
            else
                mkdir dart && unzip -q {{ dart_zip }} -d dart
                mkdir -p "{{ bin_dir }}"
                if [ -f dart/dart-sass/sass.bat ]; then
                    cp dart/dart-sass/sass.bat "{{ bin_dir }}/sass.bat"
                    echo "Installed Dart Sass (Windows) to {{ bin_dir }}/sass.bat"
                elif [ -f dart/sass.bat ]; then
                    cp dart/sass.bat "{{ bin_dir }}/sass.bat"
                    echo "Installed Dart Sass (Windows) to {{ bin_dir }}/sass.bat"
                else
                    echo "Could not locate sass.bat in archive. Falling back to npm sass..."
                    just npm-sass
                fi
            fi
        else
            echo "Dart download failed. Falling back to npm sass..."
            just npm-sass
        fi
    else
        echo "Unsupported OS {{ os() }}. Falling back to npm sass..."
        just npm-sass
    fi

# Fallback: install sass via npm
npm-sass:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Installing sass via npm..."
    mkdir -p "{{ bin_dir }}"
    npm install -g sass
    # Create symlink or copy to local bin
    if command -v sass &> /dev/null; then
        ln -sf $(which sass) "{{ sass_bin }}" || cp $(which sass) "{{ sass_bin }}"
        echo "npm sass linked to {{ sass_bin }}"
    else
        echo "ERROR: npm sass installation failed"
        exit 1
    fi

# Ensure bin directory exists
ensure-bin:
    mkdir -p "{{ bin_dir }}"

# Remove sass binaries
clean-sass:
    rm -f {{ sass_bin }} {{ bin_dir }}/sass.bat
    echo "Removed local Sass binaries"

# Run tests
test:
    crystal spec

# Run tests with verbose output
test-verbose:
    crystal spec --verbose

# Build the application
build:
    shards build

# Build optimized release
build-release:
    shards build --release

# Run the application
run *ARGS:
    crystal run src/app.cr -- {{ ARGS }}

# Run linter (ameba)
lint:
    ameba

# Format code
fmt:
    crystal tool format

# Check formatting without modifying
fmt-check:
    crystal tool format --check

# Clean build artifacts
clean: clean-sass
    rm -rf bin/
    rm -rf lib/

# Full clean and reinstall
reinstall: clean install

# Show project info
info:
    #!/usr/bin/env bash
    echo "Carafe.cr - Jekyll-compatible static site generator"
    echo ""
    echo "Platform: {{ dart_os }}/{{ dart_arch }}"
    echo "Dart Sass: {{ dart_version }}"
    echo "Bin dir: {{ bin_dir }}"
    echo ""
    echo "Sass binary: {{ sass_bin }}"
    if [ -f "{{ sass_bin }}" ]; then
        echo "Sass version: $("{{ sass_bin }}" --version)"
    else
        echo "Sass: not installed (run 'just sass')"
    fi
