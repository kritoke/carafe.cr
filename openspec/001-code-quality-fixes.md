# OpenSpec: Carafe Code Quality Fixes

## Metadata

- **Spec ID**: carafe-quality-fixes-001
- **Status**: Partially Implemented
- **Created**: 2026-05-23
- **Author**: Code Review Team
- **Supersedes**: N/A
- **Related**: N/A

---

## Motivation

During a comprehensive code review of the Carafe static site generator, multiple bugs, security issues, race conditions, and edge cases were identified across the codebase. This spec defines fixes for all identified issues, organized by severity and system component.

---

## Issues Addressed

### 🔴 CRITICAL BUGS

#### Issue 1: Pipeline Builder Double-Detection of Layout Processor

**Location**: `src/pipeline.cr:173-178`

**Problem**: The `create_pipeline` method adds the Layout processor twice - once via `if layout_transform` and again via the `if layout_proc && !segments.includes?` block. This can cause Layout to execute multiple times.

**Current Code**:
```crystal
# Add Layout at the end
layout_transform = wildcards.find { |t| t.to == "output" }
if layout_transform
  segments << layout_transform.processor
end

# Add Layout processor at the end (if not already included)
layout_proc = transformations.find(&.from_wildcard?).try(&.processor)
if layout_proc && !segments.includes?(layout_proc)
  segments << layout_proc
end
```

**Fix**: Consolidate into a single logical check that prevents duplicate Layout processors.

```crystal
# Add Layout processor at the end (if not already included)
unless segments.any? { |seg| seg.is_a?(Processor::Layout) }
  layout_proc = transformations.find(&.from_wildcard?).try(&.processor)
  if layout_proc
    segments << layout_proc
  end
end
```

**Verification**: Add test to ensure Layout appears exactly once in any pipeline.

---

#### Issue 2: Typo in Generator::Collections

**Location**: `src/generator/collections.cr:47-52`

**Problem**: Variable assigned as `collection_paths` but referenced as `collections_paths` (wrong).

**Current Code**:
```crystal
def self.new(site : Site, directory : String) : Collections
  collection_paths = [] of String  # Right side: correct
  Dir.new(directory).each_child do |name|
    path = File.join(directory, name)
    next unless File.directory?(path)
    collection_paths << path
  end

  new(site, collections_paths)  # Error: should be collection_paths
end
```

**Fix**: Rename variable consistently.

```crystal
def self.new(site : Site, directory : String) : Collections
  collection_paths = [] of String
  Dir.new(directory).each_child do |name|
    path = File.join(directory, name)
    next unless File.directory?(path)
    collection_paths << path
  end

  new(site, collection_paths)
end
```

**Verification**: Ensure spec runs without undefined variable error.

---

#### Issue 3: Paginator `previous_page` Logic Inverted

**Location**: `src/paginator.cr:26-28`

**Problem**: When `@index=1`, `previous_page` returns `1` instead of `2`. The logic is off-by-one.

**Current Code**:
```crystal
def previous_page : Int32?
  @index > 0 ? @index : nil
end
```

**Fix**: Correct the return value to be the 1-based page number of the previous page.

```crystal
def previous_page : Int32?
  @index > 0 ? @index + 1 : nil
end
```

**Verification**: Test with multi-page pagination where:
- Page 2: `previous_page` returns `1`
- Page 3: `previous_page` returns `2`

---

### 🟠 SECURITY ISSUES

#### Issue 4: Path Traversal in Layout Loading

**Location**: `src/processor/layout.cr:72-85`

**Problem**: The glob pattern `Dir[file_pattern]` could match files outside the layouts directory if symlinks exist. The `sanitize_path` check is applied *after* glob evaluation.

**Current Code**:
```crystal
def load_layout(layout_name : String) : {String, Frontmatter}
  safe_name = Security.sanitize_filename(layout_name)
  file_pattern = File.join(File.expand_path(layouts_path, @site.site_dir), "#{safe_name}.*")
  file_path = Dir[file_pattern].first?

  raise "Layout not found: ..." unless file_path

  safe_path = Security.sanitize_path(File.expand_path(layouts_path, @site.site_dir), file_path)
  raise "Layout path traversal detected" if safe_path.nil?
```

**Fix**: Validate the glob root and match results. Reject symlinks entirely.

```crystal
def load_layout(layout_name : String) : {String, Frontmatter}
  safe_name = Security.sanitize_filename(layout_name)
  raise "Invalid layout name" if safe_name.nil?

  layouts_root = File.expand_path(layouts_path, @site.site_dir)
  layouts_root = layouts_root.gsub("\\", "/")

  file_pattern = File.join(layouts_root, "#{safe_name}.*")

  # Find a direct child with a supported extension
  file_path = find_layout_file(layouts_root, safe_name)

  raise "Layout not found: #{layout_name.inspect} (layouts_path: #{layouts_path})" unless file_path

  # Final security validation
  resolved = File.expand_path(file_path)
  resolved = resolved.gsub("\\", "/")
  unless resolved.starts_with?(layouts_root + "/")
    raise "Layout path traversal detected"
  end

  File.open(file_path) do |file|
    frontmatter = Frontmatter.read_frontmatter(file) || Frontmatter.new
    content = file.gets_to_end
    return content, frontmatter
  end
end

private def find_layout_file(layouts_root : String, safe_name : String) : String?
  [".html", ".liquid", ".md"].each do |ext|
    path = File.join(layouts_root, "#{safe_name}#{ext}")
    return path if File.exists?(path) && !File.symlink?(path)
  end
  nil
end
```

**Verification**: Add test attempting to traverse via symlink - should raise error.

---

#### Issue 5: Remote Theme: Potential Shell Injection

**Location**: `src/plugins/themes/remote_theme.cr:98-104`

**Problem**: While not directly exploitable (parts split on `/`), using `Process.new` without escaping could be risky with unusual characters.

**Current Code**:
```crystal
tarball_url = "https://github.com/#{owner}/#{repo}/archive/refs/heads/#{default_branch}.tar.gz"
process = Process.new("curl", ["-L", "-o", temp_file, tarball_url])
```

**Fix**: Validate owner/repo format before use, and use HTTPS directly with Crystal's HTTP client.

```crystal
# Validate format before use
OWNER_REPO_REGEX = /\A[a-zA-Z0-9._-]+\z/

def download_theme(owner : String, repo : String, theme_dir : String, quiet : Bool) : Nil
  unless owner.match?(OWNER_REPO_REGEX) && repo.match?(OWNER_REPO_REGEX)
    raise "Invalid owner or repository name format"
  end

  # ... download using HTTP::Client instead of curl ...
end
```

**Verification**: Test with malicious owner/repo names - should reject.

---

#### Issue 6: Race Condition in Site#find

**Location**: `src/site.cr:98-112`

**Problem**: If generators or plugins modify `@files` or collections during iteration, concurrent modification could occur.

**Current Code**:
```crystal
def find(url : String) : Resource?
  url = URI.new(path: url)
  @files.each do |file|
    return file if file.url == url
  end
  @collections.each_value do |collection|
    collection.resources.each do |resource|
      return resource if resource.url == url
    end
  end
end
```

**Fix**: Create a snapshot copy for iteration, or add mutex protection.

```crystal
require "mutex"

class Carafe::Site
  # ... existing properties ...
  @resource_lock : Mutex = Mutex.new

  def find(url : String) : Resource?
    url = URI.new(path: url)
    @resource_lock.synchronize do
      @files.each do |file|
        return file if file.url == url
      end
      @collections.each_value do |collection|
        collection.resources.each do |resource|
          return resource if resource.url == url
        end
      end
    end
    nil
  end

  # Safe accessor for resources that need mutation
  def each_resource(&)
    @resource_lock.synchronize do
      yield @files
      @collections.each_value { |c| yield c.resources }
    end
  end
end
```

**Verification**: Add test that mutates collections during concurrent find operations.

---

### 🟡 EDGE CASES & LOGIC BUGS

#### Issue 7: Circular Include Detection in IncludeHandler

**Location**: `src/jekyll_compat/include_handler.cr:36-70`

**Problem**: If A includes B and B includes A, the `max_iterations` limit applies to the outer template, but inner calls to `Preprocessor.preprocess` bypass it, potentially causing stack overflow.

**Current Code**:
```crystal
def process(template : String, ctx : IncludeContext) : String
  iteration = 0
  while template.includes?("{% include") && iteration < ctx.max_iterations
    iteration += 1
    template = template.gsub(/{%\s*include\s+([^%]+?)%}/) do
      # ...
      expand(content, ctx)  # Could recursively process includes
    end
  end
  template
end
```

**Fix**: Track visited includes in the context to detect cycles.

```crystal
struct IncludeContext
  getter includes_path : String
  getter site_path : String
  getter theme_dir : String?
  getter max_iterations : Int32
  getter visited_includes : Set(String)

  def initialize(@includes_path : String, @site_path : String, @theme_dir : String? = nil,
                  @max_iterations : Int32 = 100)
    @visited_includes = Set(String).new
  end

  def visit(include_name : String) : Bool
    return false if visited_includes.includes?(include_name)
    visited_includes.add(include_name)
    true
  end

  def reset
    @visited_includes.clear
  end
end

def process(template : String, ctx : IncludeContext) : String
  iteration = 0
  original_template = template

  while template.includes?("{% include") && iteration < ctx.max_iterations
    iteration += 1
    new_template = template.gsub(/{%\s*include\s+([^%]+?)%}/) do
      content = $1
      if has_params?(content)
        "{% include #{content}%}"
      else
        expand(content, ctx)
      end
    end

    if new_template == template
      break
    end

    template = new_template
  end

  if iteration >= ctx.max_iterations
    "<!-- Include processing exceeded max iterations (possible circular includes) --><!-- #{original_template[0..100]}... -->"
  else
    template
  end
end

private def expand(content : String, ctx : IncludeContext) : String
  parts = content.split(/\s+/)
  raw_file = parts.first.lstrip('/')

  unless ctx.visit(raw_file)
    return "<!-- Circular include detected: #{raw_file} -->"
  end

  # ... rest of expand logic ...
end
```

**Verification**: Add test with circular includes - should handle gracefully.

---

#### Issue 8: Empty Frontmatter Handling

**Location**: `src/frontmatter.cr:39-52`

**Problem**: If source is empty or contains only comments/whitespace, YAML parses to `Null`, which silently returns an empty Frontmatter. This may mask configuration errors.

**Current Code**:
```crystal
def self.parse(source : String) : Frontmatter?
  unless Security.validate_content_size(source)
    raise "Frontmatter content exceeds maximum size"
  end

  yaml = YAML.parse(source)
  case raw = yaml.raw
  when Hash
    new(raw)
  when Nil
    new
  else
    raise "invalid frontmatter"
  end
end
```

**Fix**: Log a warning for empty frontmatter or add explicit comment-only check.

```crystal
def self.parse(source : String) : Frontmatter?
  unless Security.validate_content_size(source)
    raise "Frontmatter content exceeds maximum size"
  end

  # Check for significant content
  stripped = source.strip
  if stripped.empty? || stripped =~ /\A#.*\z/
    return Frontmatter.new
  end

  yaml = YAML.parse(source)
  case raw = yaml.raw
  when Hash
    new(raw)
  when Nil
    # If parse succeeded but returns nil, the content was likely empty
    # Check if there was meaningful content that parsed to nothing
    unless source.strip.empty?
      STDERR.puts "Warning: Frontmatter parsed to empty hash for #{source[0..50]}..."
    end
    new
  else
    raise "invalid frontmatter"
  end
end
```

**Verification**: Test with empty files, comment-only files, whitespace files.

---

#### Issue 9: Date Parsing Silent Fallback

**Location**: `src/resource.cr:75-105`

**Problem**: If a user misspells a date format, the fallback to midnight today happens silently with no warning.

**Current Code**:
```crystal
def date : Time do
  if date = self["date"]?
    case raw = date.raw
    when Time
      raw
    when String
      if raw.empty?
        Time.local.at_beginning_of_day
      else
        begin
          Time.parse(raw, "%Y-%m-%d %H:%M:%S %z", Time::Location.local)
        rescue
          begin
            Time.parse(raw, "%Y-%m-%d %H:%M", Time::Location.local)
          rescue
            begin
              Time.parse(raw, "%Y-%m-%d", Time::Location.local)
            rescue
              Time.local.at_beginning_of_day  # Silent fallback!
            end
          end
        end
      end
    else
      Time.local.at_beginning_of_day
    end
  elsif date = date_and_shortname_from_slug.first
    date
  else
    Time.local.at_beginning_of_day
  end
end
```

**Fix**: Log unrecognized date formats for debugging.

```crystal
private DATE_FORMATS = [
  "%Y-%m-%d %H:%M:%S %z",
  "%Y-%m-%d %H:%M:%S",
  "%Y-%m-%d %H:%M",
  "%Y-%m-%d",
  "%Y/%m/%d %H:%M:%S",
  "%Y/%m/%d",
  "%d-%m-%Y",
  "%m-%d-%Y",
  "%d %b %Y",
  "%b %d, %Y",
]

def date : Time do
  if date = self["date"]?
    case raw = date.raw
    when Time
      raw
    when String
      if raw.empty?
        Time.local.at_beginning_of_day
      else
        parsed = try_parse_date(raw)
        if parsed
          parsed
        else
          STDERR.puts "Warning: Could not parse date '#{raw}' in #{@slug}, using midnight today"
          Time.local.at_beginning_of_day
        end
      end
    else
      Time.local.at_beginning_of_day
    end
  elsif date = date_and_shortname_from_slug.first
    date
  else
    Time.local.at_beginning_of_day
  end
end

private def try_parse_date(raw : String) : Time?
  DATE_FORMATS.each do |fmt|
    begin
      return Time.parse(raw, fmt, Time::Location.local)
    rescue
    end
  end
  nil
end
```

**Verification**: Test with various date formats, including invalid ones.

---

#### Issue 10: Host Binding Error Handling

**Location**: `src/server.cr:20-27`

**Problem**: If binding fails (port in use, permission denied), exception propagates without a helpful message.

**Current Code**:
```crystal
def start
  address = @server.bind @uri
  puts "Listening on #{address}"
  @server.listen
end
```

**Fix**: Add error handling with retry suggestion.

```crystal
def start
  begin
    address = @server.bind @uri
    puts "Listening on #{address}"
    @server.listen
  rescue ex : Errno
    if ex.errno == Errno::EADDRINUSE
      STDERR.puts "Error: Port #{@uri.port} is already in use."
      STDERR.puts "Try specifying a different port with --port=PORT"
    elsif ex.errno == Errno::EACCES
      STDERR.puts "Error: Permission denied to bind to port #{@uri.port}."
      STDERR.puts "Try using a port above 1024"
    else
      STDERR.puts "Error: Server could not bind to #{@uri.host}:#{@uri.port}"
      STDERR.puts ex.message
    end
    raise ex
  end
end
```

**Verification**: Test with port already in use and insufficient permissions.

---

#### Issue 11: Pagination `per_page` Returns Items, Not Config

**Location**: `src/paginator.cr:20-22`

**Problem**: The `per_page` method returns the actual number of items on the current page, not the configured limit.

**Current Code**:
```crystal
def per_page : Int32
  @items.size
end
```

**Fix**: Store and return the configured per-page value.

```crystal
class Carafe::Paginator
  getter items : Array(Resource)
  getter index : Int32
  getter pages : Array(Resource)
  getter per_page_limit : Int32  # Store configured limit

  property! next : Resource
  property! previous : Resource
  property! first : Resource
  property! last : Resource

  def per_page : Int32
    per_page_limit
  end

  def initialize(@items : Array(Resource), @index : Int, @pages : Array(Resource), @per_page_limit : Int32 = @items.size)
  end
end
```

**Verification**: Test that `paginator.per_page` returns configured value, not actual count.

---

#### Issue 12: Plugin Cleanup Not Guaranteed

**Location**: `src/site.cr:44-57`

**Problem**: The `at_exit` cleanup handler is commented out, meaning temporary files may not be cleaned up.

**Current Code**:
```crystal
private def initialize_temp_file_management
  cleanup_previous_temporary_files

  # NOTE: Commented out for testing purposes to allow server spec to pass
  # at_exit do
  #   cleanup_temporary_files
  # end
end
```

**Fix**: Make cleanup a first-class concern, not tied to at_exit only.

```crystal
class Carafe::Site
  @cleanup_hooks = [] of Nil

  def on_cleanup(&block : Site -> Nil)
    @cleanup_hooks << block
  end

  def cleanup
    @cleanup_hooks.each do |hook|
      begin
        hook.call(self)
      rescue ex
        STDERR.puts "Cleanup error: #{ex.message}"
      end
    end

    # Cleanup temporary files in includes directory
    cleanup_temporary_files
  end

  private def cleanup_temporary_files
    includes_dir = File.join(site_dir, config.includes_dir)
    if Dir.exists?(includes_dir)
      Dir.glob(File.join(includes_dir, "*.liquid")).each do |liquid_file|
        original_html = liquid_file.sub(/\.liquid$/, ".html")
        File.delete(liquid_file) if File.exists?(original_html)
      end
    end
  end
end

# In CLI:
def run_serve(options)
  # ...
  site.on_cleanup do |s|
    s.plugin_manager.plugins.each do |plugin|
      plugin.cleanup(s) if plugin.responds_to?(:cleanup)
    end
  end

  # Register default cleanup for temporary files
  site.on_cleanup { |s| s.cleanup_temporary_files }

  trap(Signal::INT) do
    puts "\nShutting down..."
    site.cleanup
    exit
  end

  server.start
end
```

**Verification**: Test that SIGINT triggers cleanup and temporary files are removed.

---

### 🔵 BEST PRACTICE ISSUES

#### Issue 13: Global State in LiquidFilters

**Location**: `src/jekyll_compat/liquid_filters.cr:18-30`

**Problem**: Class variables `@@site_url` and `@@baseurl` are used across filters, not thread-safe for concurrent site builds.

**Current Code**:
```crystal
module LiquidFilters
  extend self

  @@site_url : String = ""
  @@baseurl : String = ""

  def site_url=(url : String)
    @@site_url = url
  end
```

**Fix**: Thread-local storage or pass context explicitly.

```crystal
require "Thread"

struct FilterContext
  property site_url : String = ""
  property baseurl : String = ""
end

# Thread-local context
thread_local property filter_context : FilterContext = FilterContext.new

macro with_filter_context
  previous_def
  {{ yield }}
end

# Filter initialization in CLI for each site:
# site.config.filter_context = FilterContext.new
# site.config.filter_context.baseurl = site.config.baseurl
```

**Verification**: Test concurrent builds with different baseurl values.

---

#### Issue 14: Over-Broad Exception Handling

**Location**: `src/processor/liquid.cr:40-47`

**Problem**: Catching all exceptions and returning original source could hide legitimate errors.

**Current Code**:
```crystal
def process(resource : Resource, input : IO, output : IO) : Bool
  # ...
  rendered = render_liquid(source, resource)
  output << rendered
  true
rescue ex
  STDERR.puts "ERROR rendering Liquid in #{resource.slug}: #{ex.message}"
  input.rewind
  IO.copy(input, output)
  true  # Always returns true, hiding errors!
end
```

**Fix**: Distinguish between parse errors (recoverable) and render errors (may not be).

```crystal
rescue ex : Liquid::ParseError
  STDERR.puts "ERROR parsing Liquid in #{resource.slug}: #{ex.message}"
  input.rewind
  IO.copy(input, output)
  true
rescue ex
  STDERR.puts "ERROR rendering Liquid in #{resource.slug}: #{ex.message}"
  raise ex  # Re-raise non-recoverable errors in build mode
end
```

**Verification**: Test with syntax errors - build should fail loudly. Add `--no-strict` flag to allow continue.

---

#### Issue 15: Missing Size Check for Includes

**Location**: `src/jekyll_compat/include_handler.cr:57-59`

**Problem**: Included files are read without size validation, potentially allowing large file inclusion.

**Current Code**:
```crystal
if path = ctx.resolve(file)
  # ... security checks ...
  body = File.read(safe_path).rstrip  # No size check!
end
```

**Fix**: Add size validation before reading.

```crystal
MAX_INCLUDE_SIZE = 1_048_576  # 1MB

private def expand(content : String, ctx : IncludeContext) : String
  # ...
  if path = ctx.resolve(file)
    # Security: Validate the resolved path is within the includes directory
    abs_includes = File.expand_path(ctx.includes_path)
    safe_path = Security.sanitize_path(abs_includes, path)
    if safe_path.nil?
      return "<!-- Include blocked: path traversal --><!-- #{file} -->"
    end

    # Security: Check file size before reading
    file_size = File.size(safe_path)
    if file_size > MAX_INCLUDE_SIZE
      return "<!-- Include blocked: file too large (#{file_size} bytes) --><!-- #{file} -->"
    end

    body = File.read(safe_path).rstrip
    # ...
  end
end
```

**Verification**: Create a large include file - should be rejected.

---

## Implementation Phases

### Phase 1: Critical Bugs (High Priority)
1. Pipeline Builder Double-Detection
2. Collections Typo
3. Paginator Logic Inversion

### Phase 2: Security Issues (High Priority)
4. Layout Path Traversal Fix
5. Remote Theme Input Validation
6. Site Resource Lock

### Phase 3: Edge Cases (Medium Priority)
7. Circular Include Detection
8. Empty Frontmatter Warning
9. Date Parsing Logging
10. Host Binding Errors
11. Pagination `per_page` Fix
12. Cleanup Guarantees

### Phase 4: Best Practices (Lower Priority)
13. Global State Encapsulation
14. Exception Handling Refinement
15. Include Size Validation

---

## Test Plan

For each issue:

1. **Write failing test** that demonstrates the issue
2. **Implement fix** following the spec above
3. **Verify test passes** with the fix
4. **Check for regressions** in related functionality

### Required Test Files:
- `spec/issues/pipeline_builder_spec.cr`
- `spec/issues/collections_generator_spec.cr`
- `spec/issues/paginator_spec.cr`
- `spec/issues/layout_security_spec.cr`
- `spec/issues/remote_theme_security_spec.cr`
- `spec/issues/site_concurrency_spec.cr`
- `spec/issues/circular_include_spec.cr`
- `spec/issues/frontmatter_parse_spec.cr`
- `spec/issues/date_parsing_spec.cr`
- `spec/issues/server_binding_spec.cr`
- `spec/issues/cleanup_spec.cr`
- `spec/issues/liquid_filter_spec.cr`

---

## Backward Compatibility

All fixes maintain API compatibility:
- Pipeline changes affect internal processing only
-paginator.per_page` behavior fix: non-breaking (sites should get correct value)
- Cleanup improvements: additive (doesn't break existing functionality)

---

## References

- Original Code Review: [Notion link]
- Related Specs: N/A
- Issue Tracker: N/A
