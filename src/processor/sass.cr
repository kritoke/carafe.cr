require "sassd"
require "liquid"
require "../processor"

module LiquidAnyHelper
  extend self

  def new_string(value : String) : Liquid::Any
    Liquid::Any.new(value)
  end

  def new_hash(value : Hash(String, LiquidAny)) : Liquid::Any
    Liquid::Any.new(value)
  end

  def new_array(value : Array(LiquidAny)) : Liquid::Any
    Liquid::Any.new(value)
  end

  def new_numeric(value : Int32 | Int64 | Float64 | Bool) : Liquid::Any
    Liquid::Any.new(value)
  end
end

class Carafe::Processor::Sass < Carafe::Processor
  # Type placeholder for Liquid::Any - used in hash type declarations
  private alias LiquidAnyType = LiquidAny

  transforms "sass": "css", "scss": "css"

  getter include_path : String
  property site : Site?

  def initialize(site : Site)
    # Default to the sass binary bundled with sassd.cr
    # Using {{__DIR__}} ensures we find the binary relative to the source code
    # even when carafe is executed from a different working directory.
    bundled_sass = File.expand_path("../../lib/sassd/bin/sass", {{ __DIR__ }})

    # Set min_version to match our bundled sass binary
    # This can be overridden by config.sass_bin if using a different version
    ::Sass.min_version = "1.100.0"

    if File.exists?(bundled_sass)
      ::Sass.bin_path = bundled_sass
    end

    if bin = site.config.sass_bin
      ::Sass.bin_path = bin
    end

    @include_path = File.join(site.config.source, "_sass")
    @site_dir = site.site_dir
    @site = site
  end

  # Get the theme sass path dynamically (for remote themes integrated during generation)
  # Looks for any subdirectory in _sass that might be from a remote theme
  private def get_theme_sass_path : String?
    if site = @site
      sass_dir = File.join(site.config.site_dir, "_sass")
      return nil unless Dir.exists?(sass_dir)
      
      # Find any subdirectory that could be from a theme
      # (themes typically put their sass in a subdirectory like "minimal-mistakes")
      Dir.each_child(sass_dir) do |entry|
        path = File.join(sass_dir, entry)
        if Dir.exists?(path) && entry != "sass"
          return path
        end
      end
    end
    nil
  end

  def process(resource : Resource, input : IO, output : IO) : Bool
    case resource.extname
    when ".sass"
      indented_syntax = true
    when ".scss"
      indented_syntax = false
    else
      return false
    end

    source = input.gets_to_end

    if source.starts_with?("---")
      # Strip front matter
      source = source.sub(/\A---.*?---\n?/m, "")

      # Render Liquid tags using the site context
      if site = @site
        source = render_liquid_variables(source, site, resource)
      end
    end

    # Use the new Config-based API for cleaner configuration
    load_paths = [File.join(@site_dir, @include_path)]
    
    # Add theme sass path if it exists (for remote themes)
    if theme_sass = get_theme_sass_path
      load_paths.insert(0, theme_sass)  # Theme sass first for overrides
    end
    
    config = ::Sass::Config.new(
      style: "expanded",
      load_paths: load_paths,
      is_indented_syntax_src: indented_syntax
    )
    rendered = ::Sass.compile(source, config)
    output << rendered

    true
  end

  # Render Liquid variables in SCSS source
  # This allows themes to use {{ site.variable }} syntax in SCSS files
  private def render_liquid_variables(source : String, site : Site, resource : Resource) : String
    liquid_context = LiquidContext.new

    # Set site data - deeply sanitize to ensure no nil values
    site_hash = build_site_hash(site)
    liquid_context.set("site", LiquidAnyHelper.new_hash(site_hash))

    # Set page data
    page_hash = build_page_hash(resource)
    liquid_context.set("page", LiquidAnyHelper.new_hash(page_hash))

    # Render the Liquid template
    begin
      template = LiquidTemplate.parse(source)
      rendered = template.render(liquid_context)
      rendered
    rescue ex
      STDERR.puts "ERROR rendering Liquid in SCSS file #{resource.slug}:"
      STDERR.puts ex.message
      # Return original source if rendering fails
      source
    end
  end

  # Build a simplified site hash for Liquid rendering in SCSS
  private def build_site_hash(site : Site) : Hash(String, LiquidAnyType)
    site_hash = build_basic_sass_site_config(site)
    add_unmapped_sass_config(site_hash, site)
    site_hash
  end

  private def build_basic_sass_site_config(site : Site) : Hash(String, LiquidAnyType)
    site_hash = new_liquid_any_hash
    site_hash["title"] = LiquidAnyHelper.new_string(site.config["title"]?.try(&.as_s) || "")
    site_hash["name"] = LiquidAnyHelper.new_string(site.config["name"]?.try(&.as_s) || "")
    site_hash["description"] = LiquidAnyHelper.new_string(site.config["description"]?.try(&.as_s) || "")
    site_hash["url"] = LiquidAnyHelper.new_string(site.config["url"]?.try(&.as_s) || "")
    site_hash["baseurl"] = LiquidAnyHelper.new_string(site.config["baseurl"]?.try(&.as_s) || "")

    if skin = site.config["minimal_mistakes_skin"]?
      site_hash["minimal_mistakes_skin"] = LiquidAnyHelper.new_string(skin.as_s)
    end

    site_hash
  end

  private def add_unmapped_sass_config(site_hash : Hash(String, LiquidAnyType), site : Site) : Nil
    site.config.yaml_unmapped.each do |k, v|
      key = k.to_s
      next if site_hash.has_key?(key)

      case raw = v.raw
      when String
        site_hash[key] = LiquidAnyHelper.new_string(raw)
      when Int32, Int64, Float64, Bool
        site_hash[key] = LiquidAnyHelper.new_numeric(raw)
      when Nil
        # Skip nil values
      when Hash
        hash = new_liquid_any_hash
        raw.each do |yaml_key, yaml_value|
          hash_key = yaml_key.is_a?(String) ? yaml_key : yaml_key.to_s
          hash[hash_key] = convert_yaml_to_liquid(yaml_value)
        end
        site_hash[key] = LiquidAnyHelper.new_hash(hash)
      when Array
        array = raw.map { |item| convert_yaml_to_liquid(item) }
        site_hash[key] = LiquidAnyHelper.new_array(array)
      else
        site_hash[key] = LiquidAnyHelper.new_string(raw.to_s)
      end
    end
  end

  # Build a simplified page hash for Liquid rendering in SCSS
  private def build_page_hash(resource : Resource) : Hash(String, LiquidAnyType)
    page_hash = new_liquid_any_hash

    page_hash["url"] = LiquidAnyHelper.new_string(resource.url.try(&.to_s) || "")
    page_hash["path"] = LiquidAnyHelper.new_string(resource.slug || "")

    # Add frontmatter data
    resource.frontmatter.each do |k, v|
      page_hash[k.to_s] = convert_yaml_to_liquid(v)
    end

    page_hash
  end

  # Convert YAML::Any to LiquidAnyType
  private def convert_yaml_to_liquid(value : YAML::Any) : LiquidAnyType
    case raw = value.raw
    when Hash
      hash = new_liquid_any_hash
      raw.each do |k, v|
        key = k.is_a?(String) ? k : k.to_s
        hash[key] = convert_yaml_to_liquid(v)
      end
      LiquidAnyHelper.new_hash(hash)
    when Array
      array = raw.map { |v| convert_yaml_to_liquid(v) }
      LiquidAnyHelper.new_array(array)
    when String
      LiquidAnyHelper.new_string(raw)
    when Int32, Int64, Float64, Bool
      LiquidAnyHelper.new_numeric(raw)
    when Nil
      LiquidAnyHelper.new_string("")
    else
      LiquidAnyHelper.new_string(raw.to_s)
    end
  end

  # Helper to create a new Hash with LiquidAny values
  private def new_liquid_any_hash : Hash(String, LiquidAnyType)
    {} of String => LiquidAnyType
  end
end