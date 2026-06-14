require "sassd"
require "liquid"
require "../processor"
require "./liquid_renderer"

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
  include LiquidRenderer

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

    # Render Liquid tags in SCSS/Sass files
    # Uses shared LiquidRenderer module - front matter is already stripped by resource loader
    if has_liquid_tags?(source) && (site = @site)
      source = render_liquid(source, resource, site)
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
end
