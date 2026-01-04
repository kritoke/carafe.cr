require "./site"
require "file_utils"

class Carafe::Builder
  def initialize(@site : Site)
  end

  def build
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
end
