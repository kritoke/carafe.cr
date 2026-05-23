require "set"
require "../util/security"

module Carafe::JekyllCompat
  # Maximum size for included files (1MB)
  MAX_INCLUDE_SIZE = 1_048_576

  struct IncludeContext
    getter includes_path : String
    getter site_path : String
    getter theme_dir : String?
    getter max_iterations : Int32
    getter visited_includes : Set(String)

    def initialize(@includes_path : String, @site_path : String, @theme_dir : String? = nil, @max_iterations : Int32 = 100)
      @visited_includes = Set(String).new
    end

    def visit(file : String) : Bool
      if @visited_includes.includes?(file)
        false
      else
        @visited_includes.add(file)
        true
      end
    end

    def resolve(filename : String) : String?
      primary = File.join(@includes_path, filename)
      return primary if File.exists?(primary)

      if theme = @theme_dir
        theme_path = File.join(theme, "_includes", filename)
        return theme_path if File.exists?(theme_path)
      end

      nil
    end
  end

  module IncludeHandler
    extend self

    def process(template : String, ctx : IncludeContext) : String
      iteration = 0
      original_template = template

      while template.includes?("{% include") && iteration < ctx.max_iterations
        iteration += 1

        template = template.gsub(/{%\s*include\s+([^%]+?)%}/) do
          content = $1
          if has_params?(content)
            "{% include #{content}%}"
          else
            expand(content, ctx)
          end
        end

        break unless has_simple_includes?(template)
      end

      if iteration >= ctx.max_iterations
        "<!-- Circular include or too many includes detected --><!-- #{original_template[0..100]}... -->"
      else
        template
      end
    end

    private def has_params?(content : String) : Bool
      !!(content =~ /\s+[A-Za-z_]\w*=/)
    end

    private def has_simple_includes?(template : String) : Bool
      template.scan(/{%\s*include\s+([^%]+?)%}/).any? { |match| !has_params?(match[1]) }
    end

    private def expand(content : String, ctx : IncludeContext) : String
      parts = content.split(/\s+/)
      raw_file = parts.first

      # Security: Sanitize the filename
      file = Security.sanitize_filename(raw_file.delete('"').lstrip('/'))

      if file.nil?
        return "<!-- Invalid include filename --><!-- #{raw_file} -->"
      end

      # Check for circular includes
      unless ctx.visit(file)
        return "<!-- Circular include detected: #{file} -->"
      end

      if path = ctx.resolve(file)
        # Security: Validate the resolved path is within the includes directory
        # The path from resolve() is already the full path (e.g., spec/fixtures/.../foo.html)
        # Convert to absolute path for comparison
        abs_includes = File.expand_path(ctx.includes_path)
        abs_path = File.expand_path(path) # path is already a full path, just relative

        # Verify the file is within the includes directory
        safe_path = Security.sanitize_path(abs_includes, abs_path)
        if safe_path.nil? || !File.exists?(safe_path)
          return "<!-- Include blocked: path traversal or file not found --><!-- #{file} -->"
        end

        # Security: Check file size before reading
        file_size = File.size(safe_path)
        if file_size > MAX_INCLUDE_SIZE
          return "<!-- Include blocked: file too large (#{file_size} bytes) --><!-- #{file} -->"
        end

        body = File.read(safe_path).rstrip
        body = remove_self_refs(body, file)
        Preprocessor.preprocess(body)
      else
        "<!-- Include not found: #{file} -->"
      end
    end

    private def remove_self_refs(content : String, filename : String) : String
      content.gsub(/{%\s*include\s+#{Regex.escape(filename)}\b[^%]*%}/,
        "<!-- Self-include removed: #{filename} -->")
    end
  end
end
