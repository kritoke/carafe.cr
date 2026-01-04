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
        raise Exception.new("Error running processors for collection #{collection.name}", cause: ex)
      end
    end

    # Only cleanup after successful build
    cleanup
  end

  def cleanup
    puts "DEBUG: Running cleanup for #{@site.plugin_manager.plugins.size} plugins"
    # Call cleanup on all plugins
    @site.plugin_manager.plugins.each do |plugin|
      puts "DEBUG: Checking plugin #{plugin.name} for cleanup method"
      if plugin.responds_to?(:cleanup)
        puts "DEBUG: Calling cleanup on #{plugin.name}"
        plugin.cleanup(@site)
      end
    end
  end

  def run_processors(resources : Array(Resource))
    resources.each do |resource|
      puts "  #{resource.slug}"
      output_relative_path = resource.output_path
      output_path = File.join(@site.config.destination, output_relative_path)

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
