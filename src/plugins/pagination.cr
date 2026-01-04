require "../carafe"

class Carafe::Plugins::Pagination < Carafe::Plugin
  class Generator < Carafe::Generator
    getter priority : Carafe::Priority = Carafe::Priority::LOW

    def initialize(site : Carafe::Site)
      super(site)
    end

    def generate : Nil
      paginator_resources = [] of Carafe::Resource
      site.files.each do |resource|
        if config = resource["paginate"]?
          paginate_resource(resource, config, paginator_resources)
        end
      end
      site.files.concat paginator_resources

      site.collections.each_value do |collection|
        paginator_resources = [] of Carafe::Resource
        collection.resources.each do |resource|
          if config = resource["paginate"]?
            paginate_resource(resource, config, paginator_resources)
          end
        end
        collection.resources.concat paginator_resources
      end
    end

    def paginate_resource(resource : Carafe::Resource, config : YAML::Any, paginator_resources : Array(Carafe::Resource))
      per_page = config["per_page"]?.try(&.as_i) || 25
      permalink = config["permalink"]?.try(&.as_s)

      items = [] of Carafe::Resource

      if key = config["collection"]?
        items = site.collections[key].resources
        permalink ||= "/#{key}/page/:num/"
      elsif config["data"]?
        raise "not implemented"
      end

      if config["sort"]?
        items.sort!
      end

      if config["sort_descending"]?
        items.reverse!
      end

      chunks = items.each_slice(per_page)
      pages = [] of Carafe::Resource

      chunks.each_with_index do |chunk_items, i|
        paginator = Carafe::Paginator.new(chunk_items, i + 1, pages)
        if i.zero?
          resource.paginator = paginator
          pages << resource
        else
          clone = Carafe::Resource.new(site, resource.slug, resource.content, frontmatter: resource.frontmatter.clone, defaults: resource.defaults)
          clone.frontmatter.merge!(Carafe::Frontmatter{"permalink" => permalink})
          clone.paginator = paginator
          pages << clone
          paginator_resources << clone
        end
      end

      pages.each_cons(2) do |cons|
        if paginator = cons[0].paginator
          paginator.next = cons[1]
          paginator.last = pages.last
        end
        if paginator = cons[1].paginator
          paginator.previous = cons[0]
          paginator.first = pages.first
        end
      end
    end
  end

  def name : String
    "pagination"
  end

  def version : String
    "0.1.0"
  end

  def enabled?(config : Carafe::Config) : Bool
    # Check if paginate is configured in _config.yml
    paginate_value = config["paginate"]?

    if paginate_value
      return true if paginate_value.as_i? || paginate_value.as_bool?
    end

    false
  end

  def register(site : Carafe::Site) : Nil
    # Add the pagination generator to the site
    site.generators << Generator.new(site)
  end
end

# Register this plugin
Carafe::Plugin.register_implementation(Carafe::Plugins::Pagination)
