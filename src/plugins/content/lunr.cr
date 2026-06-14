require "../plugin"
require "json"

class Carafe::Plugins::LunrPlugin < Carafe::Plugin
  def name : String
    "lunr"
  end

  def version : String
    "0.1.0"
  end

  def enabled?(config : Carafe::Config) : Bool
    search_value = config["search"]?

    if search_value
      return true if search_value.as_bool? || search_value.as_h?
    end

    false
  end

  def register(site : Carafe::Site) : Nil
    site.generators << Generator.new(site)
  end

  class Generator < Carafe::Generator
    getter priority : Carafe::Priority = Carafe::Priority::LOW

    def initialize(site : Carafe::Site)
      super(site)
    end

    def generate : Nil
      documents = [] of Hash(String, JSON::Any)

      site.files.each do |resource|
        next unless should_index?(resource)
        doc = build_document(resource)
        documents << doc if doc
      end

      site.collections.each_value do |collection|
        collection.resources.each do |resource|
          next unless should_index?(resource)
          doc = build_document(resource)
          documents << doc if doc
        end
      end

      generate_search_index(documents)
    end

    private def should_index?(resource : Carafe::Resource) : Bool
      url = resource.url
      return false unless url

      url.path.ends_with?(".css") ||
        url.path.ends_with?(".js") ||
        url.path.ends_with?(".map") ||
        url.path.ends_with?(".dwarf") ||
        url.path.ends_with?(".cr") ||
        url.path.ends_with?(".gem") ||
        url.path.ends_with?(".lock") ||
        url.path.ends_with?(".nix") ||
        url.path.includes?("carafe") ||
        url.path.includes?("README") ? false : true
    end

    private def build_document(resource : Carafe::Resource) : Hash(String, JSON::Any)?
      return unless resource.url

      title = resource["title"]?.try(&.as_s) || resource.slug
      content = extract_content(resource)

      {
        "url"     => JSON::Any.new(resource.url.to_s),
        "title"   => JSON::Any.new(title),
        "content" => JSON::Any.new(content),
        "date"    => JSON::Any.new(resource["date"]?.try(&.as_s) || ""),
      }
    end

    private def extract_content(resource : Carafe::Resource) : String
      content = resource.content || ""

      unless content.valid_encoding?
        content = content.scrub
      end

      content.gsub(/<[^>]*>/, "")
        .gsub(/\s+/, " ")
        .strip
    end

    private def generate_search_index(documents : Array(Hash(String, JSON::Any))) : Nil
      index_data = {
        "documents" => documents,
      }

      dest_dir = File.join(site.site_dir, site.config.destination)
      index_path = File.join(dest_dir, "search.json")

      Dir.mkdir_p(dest_dir) unless Dir.exists?(dest_dir)

      File.write(index_path, index_data.to_json)
    end
  end
end

Carafe::Plugin.register_implementation(Carafe::Plugins::LunrPlugin)
