require "../carafe"
require "crinja"

class Carafe::Plugins::CarafeTags < Carafe::Plugin
  def name : String
    "carafe_tags"
  end

  def version : String
    "0.1.0"
  end

  def enabled?(config : Carafe::Config) : Bool
    # Always enabled for Jekyll compatibility
    true
  end

  def register(site : Carafe::Site) : Nil
    # Add a generator to make templates Jekyll-compatible
    site.generators << Generator.new(site)
  end

  class Generator < Carafe::Generator
    getter priority : Carafe::Priority = Carafe::Priority::HIGH

    def initialize(site : Carafe::Site)
      super(site)
    end

    def generate : Nil
      # Process template files to make them Jekyll-compatible
      template_dirs = [
        File.join(site.site_dir, site.config.layouts_dir),
        File.join(site.site_dir, site.config.includes_dir),
      ]

      template_dirs.each do |dir|
        next unless File.directory?(dir)
        process_directory(dir)
      end
    end

    private def process_directory(dir : String) : Nil
      Dir.each_child(dir) do |item|
        path = File.join(dir, item)
        if File.directory?(path)
          process_directory(path)
        else
          process_file(path)
        end
      end
    end

    private def process_file(path : String) : Nil
      ext = File.extname(path).downcase
      text_extensions = [".html", ".htm", ".md", ".markdown", ".liquid", ".yml", ".yaml", ".css", ".js", ".scss", ".sass"]

      return unless text_extensions.includes?(ext)

      begin
        content = File.read(path)
        original = content.dup

        # Replace Jekyll's include_cached with include
        content = content.gsub(/\{%\s*include_cached\s+/, "{% include ")

        # Replace Jekyll's 'contains' operator with filter syntax
        # {% if var1 contains var2 %} becomes {% if var1 | contains: var2 %}
        # Handle both simple variables and complex expressions
        # Preserve whitespace control characters (-)
        content = content.gsub(/(\{%[-\s]*if[-\s]+[^%\}]*?)\s+contains\s+([^%\}]*?[-\s]*%\})/m) do |_|
          "#{$1} | contains: #{$2}"
        end

        if content != original
          File.write(path, content)
        end
      rescue ex : Exception
        # Skip files that can't be processed
      end
    end
  end
end

# Register this plugin
Carafe::Plugin.register_implementation(Carafe::Plugins::CarafeTags)
