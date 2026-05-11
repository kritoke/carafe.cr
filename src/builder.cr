require "./site"
require "./jekyll_compat"
require "file_utils"

class Carafe::Builder
  @copied_includes : Array(String) = [] of String

  def initialize(@site : Site)
  end

  def build
    copy_html_includes

    success = false
    begin
      run_processors(@site.files)

      @site.collections.each_value do |collection|
        next unless collection.output?
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

      success = true
    ensure
      cleanup_copied_includes

      cleanup unless success
    end
  end

  def cleanup
    @site.plugin_manager.plugins.each do |plugin|
      if plugin.responds_to?(:cleanup)
        plugin.cleanup(@site)
      end
    end
  end

  def run_processors(resources : Array(Resource))
    puts "Processing #{resources.size} resources"
    resources.each do |resource|
      puts "  Processing: #{resource.slug}"
      output_relative_path = resource.output_path
      if @site.config.destination.starts_with?("/")
        output_path = File.join(@site.config.destination, output_relative_path)
      else
        output_path = File.join(@site.site_dir, @site.config.destination, output_relative_path)
      end
      puts "  Output path: #{output_path}"

      FileUtils.mkdir_p(File.dirname(output_path))

      if File.directory?(File.dirname(output_path))
        puts "  Directory exists: #{File.dirname(output_path)}"
      else
        puts "  Directory does NOT exist: #{File.dirname(output_path)}"
      end

      File.open(output_path, "w") do |file|
        begin
          @site.run_processor(file, resource)
        rescue ex
          raise Exception.new("Error running processor for #{resource.slug}: #{ex.message}", cause: ex)
        end
      end

      if File.exists?(output_path)
        puts "  File created successfully: #{File.size(output_path)} bytes"
      else
        puts "  ERROR: File was NOT created!"
      end
    end
  end

  def copy_html_includes
    includes_dir = File.join(@site.site_dir, @site.config.includes_dir)
    @copied_includes = JekyllCompat::FileConverter.copy_html_includes(includes_dir)
  end

  def cleanup_copied_includes
    @copied_includes.each do |file|
      File.delete(file) if File.exists?(file)
    end
    @copied_includes.clear
  end
end
