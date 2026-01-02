require "sassd"
require "crinja"
require "../processor"

class Carafe::Processor::Sass < Carafe::Processor
  transforms "sass": "css", "scss": "css"

  getter include_path : String
  property site : Site?

  def self.new(site : Site)
    # Default to the sass binary located within the carafe project directory.
    # Using {{__DIR__}} ensures we find the binary relative to the source code
    # even when carafe is executed from a different working directory.
    project_bin = File.expand_path("../../bin/sass", {{__DIR__}})

    if File.exists?(project_bin)
      ::Sass.bin_path = project_bin
    end

    if bin = site.config.sass_bin
      ::Sass.bin_path = bin
    end

    instance = new(File.join(site.config.source, "_sass"), site.site_dir)
    instance.site = site
    instance
  end

  def initialize(@include_path : String = "_sass", @site_dir : String = ".")
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

      # Render Liquid/Crinja tags using the site context
      if site = @site
        source = ::Crinja.render(source, {"site" => site})
      end
    end

    rendered = ::Sass.compile(source, include_path: File.join(@site_dir, include_path), is_indented_syntax_src: indented_syntax)
    output << rendered

    true
  end
end
