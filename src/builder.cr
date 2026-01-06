require "./site"
require "file_utils"

class Carafe::Builder
  @copied_includes : Array(String) = [] of String

  def initialize(@site : Site)
  end

  def build
    # Copy .html includes to .liquid for Jekyll compatibility
    copy_html_includes

    begin
      run_processors(@site.files)

      @site.collections.each_value do |collection|
        puts "Building #{collection.name}..."
        begin
          run_processors(collection.resources)
        rescue ex
          STDERR.puts "Error processing collection #{collection.name}: #{ex.message}"
          STDERR.puts ex.backtrace.join("\n")
          if cause = ex.cause
            STDERR.puts "Caused by: #{cause.message}"
            STDERR.puts cause.backtrace.join("\n")
          end
          raise Exception.new("Error running processors for collection #{collection.name}", cause: ex)
        end
      end

      # Only cleanup after successful build
      cleanup
    ensure
      # Always clean up temporary .liquid files, even on error
      cleanup_copied_includes
    end
  end

  def cleanup
    # Call cleanup on all plugins
    @site.plugin_manager.plugins.each do |plugin|
      if plugin.responds_to?(:cleanup)
        plugin.cleanup(@site)
      end
    end
  end

  def run_processors(resources : Array(Resource))
    resources.each do |resource|
      puts "  #{resource.slug}"
      output_relative_path = resource.output_path
      output_path = File.join(@site.site_dir, @site.config.destination, output_relative_path)

      puts "    Output path: #{output_path}" if @site.config.verbose?

      FileUtils.mkdir_p(File.dirname(output_path))

      File.open(output_path, "w") do |file|
        begin
          @site.run_processor(file, resource)
        rescue ex
          raise Exception.new("Error running processor for #{resource.slug}: #{ex.message}", cause: ex)
        end
      end
    end
  end

  # Copy .html includes to .liquid for Jekyll compatibility
  # liquid.cr expects .liquid extension, but Jekyll uses .html
  # Also converts Jekyll's key=value syntax to liquid.cr's key: value syntax
  def copy_html_includes
    includes_dir = File.join(@site.site_dir, @site.config.includes_dir)

    if Dir.exists?(includes_dir)
      html_files = Dir.glob(File.join(includes_dir, "*.html"))

      html_files.each do |html_file|
        liquid_file = html_file.sub(/\.html$/, ".liquid")

        # Only process if .liquid version doesn't already exist
        unless File.exists?(liquid_file)
          content = File.read(html_file)

          # Convert Jekyll include syntax to liquid.cr compatible syntax
          # Pattern: {% include file.html key=value key2=value2 %}
          # To:      {% include file.liquid, key: "value", key2: "value2" %}
          content = content.gsub(/\{%\s*include\s+([^\s]+?)\.html(\s+.*?)?\s*%\}/) do |_match|
            template_name = $1
            params = $2

            # Build new include statement
            new_include = "{% include #{template_name}.liquid"

            # Convert parameters if present
            if params && !params.strip.empty?
              converted_params = [] of String

              # Find all key=value patterns
              # Match: key=value where key is alphanumeric and value can contain dots, brackets, etc.
              params.scan(/(\w+)=([^\s%]+)/) do |param_match|
                key = param_match[1]
                value = param_match[2]
                # Wrap value in quotes unless it's a variable
                if value =~ /^[a-zA-Z_][a-zA-Z0-9_.\[\]]*$/
                  # It's a variable reference
                  converted_params << "#{key}: #{value}"
                else
                  # It's a literal value, wrap in quotes
                  converted_params << "#{key}: \"#{value}\""
                end
              end

              # Add converted parameters with comma separator
              if converted_params.size > 0
                new_include += ", " + converted_params.join(", ")
              end
            end

            new_include + " %}"
          end

          File.write(liquid_file, content)
          @copied_includes << liquid_file
        end
      end
    end
  end

  # Clean up temporary .liquid files created from .html includes
  def cleanup_copied_includes
    @copied_includes.each do |file|
      File.delete(file) if File.exists?(file)
    end
    @copied_includes.clear
  end
end
