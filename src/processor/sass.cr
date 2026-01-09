require "sassd"
require "../processor"
require "liquid"

class Carafe::Processor::Sass < Carafe::Processor
  transforms "sass": "css", "scss": "css"

  getter include_path : String
  property site : Site?

  def initialize(site : Site)
    # Default to the sass binary located within the carafe project directory.
    # Using {{__DIR__}} ensures we find the binary relative to the source code
    # even when carafe is executed from a different working directory.
    project_bin = File.expand_path("../../bin/sass", {{ __DIR__ }})

    if File.exists?(project_bin)
      ::Sass.bin_path = project_bin
    end

    if bin = site.config.sass_bin
      ::Sass.bin_path = bin
    end

    @include_path = File.join(site.config.source, "_sass")
    @site_dir = site.site_dir
    @site = site
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

    rendered = ::Sass.compile(source, include_path: File.join(@site_dir, include_path), is_indented_syntax_src: indented_syntax)
    output << rendered

    true
  end

  # Render Liquid variables in SCSS source
  # This allows themes to use {{ site.variable }} syntax in SCSS files
  private def render_liquid_variables(source : String, site : Site, resource : Resource) : String
    liquid_context = Liquid::Context.new

    # Set site data - deeply sanitize to ensure no nil values
    site_hash = build_site_hash(site)
    liquid_context.set("site", Liquid::Any.new(site_hash))

    # Set page data
    page_hash = build_page_hash(resource)
    liquid_context.set("page", Liquid::Any.new(page_hash))

    # Render the Liquid template
    begin
      template = Liquid::Template.parse(source)
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
  private def build_site_hash(site : Site) : Hash(String, Liquid::Any)
    site_hash = {} of String => Liquid::Any

    # Add commonly used site config values
    site_hash["title"] = Liquid::Any.new(site.config["title"]?.try(&.as_s) || "")
    site_hash["name"] = Liquid::Any.new(site.config["name"]?.try(&.as_s) || "")
    site_hash["description"] = Liquid::Any.new(site.config["description"]?.try(&.as_s) || "")
    site_hash["url"] = Liquid::Any.new(site.config["url"]?.try(&.as_s) || "")
    site_hash["baseurl"] = Liquid::Any.new(site.config["baseurl"]?.try(&.as_s) || "")

    # Add minimal_mistakes_skin if present
    if skin = site.config["minimal_mistakes_skin"]?
      site_hash["minimal_mistakes_skin"] = Liquid::Any.new(skin.as_s)
    end

    # Add any unmapped YAML config values
    site.config.yaml_unmapped.each do |k, v|
      key = k.to_s
      next if site_hash.has_key?(key)

      case raw = v.raw
      when String
        site_hash[key] = Liquid::Any.new(raw)
      when Int32, Int64, Float64, Bool
        site_hash[key] = Liquid::Any.new(raw)
      when Nil
        # Skip nil values
      when Hash
        # Convert nested hashes
        hash = {} of String => Liquid::Any
        raw.each do |yaml_key, yaml_value|
          hash_key = yaml_key.is_a?(String) ? yaml_key : yaml_key.to_s
          hash[hash_key] = convert_yaml_to_liquid(yaml_value)
        end
        site_hash[key] = Liquid::Any.new(hash)
      when Array
        array = raw.map { |item| convert_yaml_to_liquid(item) }
        site_hash[key] = Liquid::Any.new(array)
      else
        site_hash[key] = Liquid::Any.new(raw.to_s)
      end
    end

    site_hash
  end

  # Build a simplified page hash for Liquid rendering in SCSS
  private def build_page_hash(resource : Resource) : Hash(String, Liquid::Any)
    page_hash = {} of String => Liquid::Any

    page_hash["url"] = Liquid::Any.new(resource.url.try(&.to_s) || "")
    page_hash["path"] = Liquid::Any.new(resource.slug || "")

    # Add frontmatter data
    resource.frontmatter.each do |k, v|
      page_hash[k.to_s] = convert_yaml_to_liquid(v)
    end

    page_hash
  end

  # Convert YAML::Any to Liquid::Any
  private def convert_yaml_to_liquid(value : YAML::Any) : Liquid::Any
    case raw = value.raw
    when Hash
      hash = {} of String => Liquid::Any
      raw.each do |k, v|
        key = k.is_a?(String) ? k : k.to_s
        hash[key] = convert_yaml_to_liquid(v)
      end
      Liquid::Any.new(hash)
    when Array
      array = raw.map { |v| convert_yaml_to_liquid(v) }
      Liquid::Any.new(array)
    when String, Int32, Int64, Float64, Bool
      Liquid::Any.new(raw)
    when Nil
      Liquid::Any.new("")
    else
      Liquid::Any.new(raw.to_s)
    end
  end
end
