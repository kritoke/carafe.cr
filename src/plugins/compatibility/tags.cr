require "../../util/security"

class Carafe::Plugins::TagsPlugin < Carafe::Plugin
  def name : String
    "jekyll_tags"
  end

  def version : String
    "0.1.0"
  end

  def enabled?(config : Carafe::Config) : Bool
    true
  end

  def register(site : Carafe::Site) : Nil
    site.generators << Generator.new(site)
  end

  class Generator < Carafe::Generator
    getter priority : Carafe::Priority = Carafe::Priority::HIGH

    def initialize(site : Carafe::Site)
      super(site)
    end

    def generate : Nil
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

        content = content.gsub(/\{%\s*include_cached\s+/, "{% include ")

        content = content.gsub(/(\{%[-\s]*if[-\s]+[^%\}]*?)\s+contains\s+([^%\}]*?[-\s]*%\})/m) do |_|
          "#{$1} | contains: #{$2}"
        end

        if content != original
          # Security: Validate the path is within the site directory
          safe_path = Security.sanitize_path(site.site_dir, path)
          if safe_path
            File.write(safe_path, content)
          end
        end
      rescue
      end
    end
  end
end

Carafe::Plugin.register_implementation(Carafe::Plugins::TagsPlugin)
