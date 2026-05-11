require "./resource"
require "./pipeline"
require "./config"
require "./collection"
require "./plugins/plugin"
require "./generator/data"
require "yaml"

class Carafe::Site
  getter config : Config

  getter site_dir : String

  getter files : Array(Resource) = [] of Resource

  # Internal storage for collections
  @collections = {} of String => Collection

  # Internal accessor for collections (for use in Carafe code)
  def collections
    @collections
  end

  getter generators : Array(Generator) = [] of Generator

  getter pipeline_builder : Pipeline::Builder

  getter plugin_manager : PluginManager

  getter data : Hash(String, ::YAML::Any) = {} of String => ::YAML::Any

  @time : Time

  def initialize(@config : Config = Config.new)
    @time = Time.local
    @site_dir = File.expand_path(config.site_dir)
    @pipeline_builder = uninitialized Pipeline::Builder
    @plugin_manager = uninitialized PluginManager
    @pipeline_builder = Pipeline::Builder.new(self)
    @plugin_manager = PluginManager.new(self)

    # Initialize temporary file management
    initialize_temp_file_management

    init_collections
  end

  private def initialize_temp_file_management
    # Cleanup any existing temporary files from previous runs (crash recovery)
    cleanup_previous_temporary_files

    # Register exit hook for cleanup
    # NOTE: Commented out for testing purposes to allow server spec to pass
    # at_exit do
    #   cleanup_temporary_files
    # end
  end

  private def cleanup_previous_temporary_files
    # Cleanup any leftover temporary files in includes directory
    includes_dir = File.join(site_dir, config.includes_dir)
    if Dir.exists?(includes_dir)
      Dir.glob(File.join(includes_dir, "*.liquid")).each do |liquid_file|
        original_html = liquid_file.sub(/\.liquid$/, ".html")
        # Only remove .liquid files that have corresponding .html files
        File.delete(liquid_file) if File.exists?(original_html)
      end
    end
  end

  private def cleanup_temporary_files
    # Call cleanup on all plugins
    plugin_manager.plugins.each do |plugin|
      if plugin.responds_to?(:cleanup)
        begin
          plugin.cleanup(self)
        rescue ex
          STDERR.puts "Error during plugin cleanup: #{ex.message}"
        end
      end
    end

    # Cleanup temporary .liquid files in includes directory
    includes_dir = File.join(site_dir, config.includes_dir)
    if Dir.exists?(includes_dir)
      Dir.glob(File.join(includes_dir, "*.liquid")).each do |liquid_file|
        original_html = liquid_file.sub(/\.liquid$/, ".html")
        File.delete(liquid_file) if File.exists?(original_html)
      end
    end
  end

  private def init_collections
    config.collections.each do |name, collection_config|
      collection = Collection.new(name, collection_config)
      collections[name] = collection
    end
  end

  def self.new(site_dir : String)
    new Config.load(site_dir)
  end

  def posts : Array(Resource)
    collections["posts"].resources
  end

  def time
    @time
  end

  def url : URI
    URI.new("http://example.com")
  end

  def run_generators
    # Load plugins - they may register additional generators
    @plugin_manager.load_from_config

    # Add core generators
    @generators << Generator::Collections.new(self)
    @generators << Generator::Files.new(self)
    @generators << Generator::Data.new(self)
    # Note: Pagination is handled by pagination plugin

    @generators.sort_by!(&.priority)

    @generators.each do |generator|
      generator.generate
    end

    @files.sort!
    @collections.each_value do |collection|
      collection.resources.sort!
    end
  end

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

  def run_processor(io : IO, resource : Resource)
    pipeline = @pipeline_builder.pipeline_for(resource)

    pipeline.pipe(io, resource)
  end

  def defaults_for(path : String, type : String) : Frontmatter
    frontmatter = Frontmatter.new

    config.defaults.each do |defaults|
      scope = defaults.scope

      glob = scope.path
      # Empty glob means "match all paths" (Jekyll behavior)
      next if glob && !glob.empty? && !File.match?(glob, path)

      scope_type = scope.type
      next if scope_type && (scope_type != type)

      frontmatter.merge!(defaults.values)
    end

    frontmatter
  end

  def register(resource : Resource)
    resource.output_ext = pipeline_builder.output_ext_for(resource)
    # Don't set URL yet - it will be set after collection is assigned
    # resource.url = Resource.url_for(resource)
  end
end
