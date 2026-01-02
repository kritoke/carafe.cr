require "./site"
require "file_utils"

class Carafe::Builder
  def initialize(@output_dir : String)
  end

  def build(site : Site)
    run_processors(site, site.files)

    site.collections.each_value do |collection|
      puts "Building #{collection.name}..."
      begin
        run_processors(site, collection.resources)
      rescue ex
        raise Exception.new("Error running processors for collection #{collection.name}", cause: ex)
      end
    end
  end

  def run_processors(site : Site, resources : Array(Resource))
    resources.each do |resource|
      puts "  #{resource.slug}"
      output_relative_path = resource.output_path
      output_path = File.join(@output_dir, output_relative_path)

      FileUtils.mkdir_p(File.dirname(output_path))

      File.open(output_path, "w") do |file|
        begin
          site.run_processor(file, resource)
        rescue ex
          raise Exception.new("Error running processor for #{resource.slug}: #{ex.message}", cause: ex)
        end
      end
    end
  end
end
