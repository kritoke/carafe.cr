require "../carafe"
require "json"

class Carafe::Plugins::Lunr < Carafe::Plugin
  def name : String
    "lunr"
  end

  def version : String
    "0.1.0"
  end

  def enabled?(config : Carafe::Config) : Bool
    # Check if search is configured in _config.yml
    search_value = config["search"]?

    if search_value
      return true if search_value.as_bool? || search_value.as_h?
    end

    false
  end

  def register(site : Carafe::Site) : Nil
    # Add a generator to create the search index
    site.generators << Generator.new(site)
  end

  class Generator < Carafe::Generator
    getter priority : Carafe::Priority = Carafe::Priority::LOW

    def initialize(site : Site)
      super(site)
    end

    def generate : Nil
      # Collect all documents to index
      documents = [] of Hash(String, JSON::Any)

      # Index files
      site.files.each do |resource|
        url = resource.url
        next unless url
        next if url.path.ends_with?(".css") || url.path.ends_with?(".js")

        doc = build_document(resource)
        documents << doc if doc
      end

      # Index collection resources
      site.collections.each_value do |collection|
        collection.resources.each do |resource|
          next unless resource.url

          doc = build_document(resource)
          documents << doc if doc
        end
      end

      # Generate the search index file
      generate_search_index(documents)
    end

    private def build_document(resource : Resource) : Hash(String, JSON::Any)?
      return nil unless resource.url

      # Extract title and content
      title = resource["title"]?.try(&.as_s) || resource.slug
      content = extract_content(resource)

      {
        "url"     => JSON::Any.new(resource.url.to_s),
        "title"   => JSON::Any.new(title),
        "content" => JSON::Any.new(content),
        "date"    => JSON::Any.new(resource["date"]?.try(&.as_s) || ""),
      }
    end

    private def extract_content(resource : Resource) : String
      # Strip HTML tags and get plain text content
      content = resource.content || ""

      # Simple HTML tag removal
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

      # Ensure destination directory exists
      Dir.mkdir_p(dest_dir) unless Dir.exists?(dest_dir)

      # Write the search index
      File.write(index_path, index_data.to_json)
    end
  end
end
