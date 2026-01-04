require "./resource"
require "./pipeline"
require "./config"
require "./collection"
require "./plugin"
require "./generator/data"
require "yaml"

@[::Crinja::Attributes(expose: [files])]
class Carafe::Site
  include ::Crinja::Object::Auto

  getter config : Config

  getter site_dir : String

  getter files : Array(Resource) = [] of Resource

  # Internal storage for collections
  @collections = {} of String => Collection

  # Internal accessor for collections (for use in Carafe code)
  @[Crinja::Attribute(ignore: true)]
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

    init_collections
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

  @[::Crinja::Attribute]
  def posts : Array(Resource)
    collections["posts"].resources
  end

  @[::Crinja::Attribute]
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
    resource.url = Resource.url_for(resource)
  end

  def crinja_attribute(value : Crinja::Value) : Crinja::Value
    case value.to_s
    when "time"
      # Jekyll compatibility: site.time returns the current time
      Crinja::Value.new(Time.local)
    when "posts"
      # Jekyll compatibility: site.posts should return the posts collection's resources
      posts_collection = @collections["posts"]?
      if posts_collection
        # Return the posts array directly (as Crinja::Value array)
        resources_array = posts_collection.resources.map do |resource|
          Crinja::Value.new(resource)
        end
        Crinja::Value.new(resources_array)
      else
        Crinja::Value.new(Crinja::Undefined.new("posts"))
      end
    when "collections"
      # Convert collections hash to an array of collection objects for Jekyll compatibility
      # In Jekyll/Liquid, {% for collection in site.collections %} iterates over collection objects
      collections_array = [] of Crinja::Value
      @collections.each do |_name, collection|
        # Convert resources array to Crinja array
        resources_array = collection.resources.map do |resource|
          # Each resource should already be Crinja-compatible
          Crinja::Value.new(resource)
        end

        collection_data = {
          "name"    => Crinja::Value.new(collection.name),
          "output"  => Crinja::Value.new(collection.defaults.output?),
          "docs"    => Crinja::Value.new(resources_array),  # Jekyll uses 'docs' for collection resources
          "resources" => Crinja::Value.new(Crinja::Undefined.new("resources"))
        }
        collections_array << Crinja::Value.new(collection_data)
      end
      Crinja::Value.new(collections_array)
    else
      result = super

      if result.undefined?
        config.crinja_attribute(value)
      else
        result
      end
    end
  end
end
