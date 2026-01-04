require "liquid"
require "../processor"
require "../liquid_filters"
require "../liquid_blocks/highlight"

class Carafe::Processor::Crinja < Carafe::Processor
  transforms "crinja": "*", "jinja": "*", "liquid": "*"

  def self.new(site : Site)
    new(
      site,

      site.site_dir)
  end

  def initialize(@site : Site = Site.new,
                 includes_dir : String = File.join(site.config.source, site.config.includes_dir),
                 site_dir : String = site.site_dir)
    @includes_dir = includes_dir
    @site_dir = site_dir
  end

  def process(resource : Resource, input : IO, output : IO) : Bool
    template_content = input.gets_to_end

    template = Liquid::Template.parse(template_content)

    # Create Liquid context
    liquid_context = Liquid::Context.new

    # Set site data - pass Hash(String, Liquid::Any) directly
    # Context.set will wrap it in Liquid::Any.new() for us
    site_hash = build_simple_site_hash()
    liquid_context.set("site", site_hash)

    # Set page data
    liquid_context.set("page", build_simple_page_hash(resource))

    # Set paginator data
    liquid_context.set("paginator", build_simple_paginator_hash(resource))

    io = IO::Memory.new
    template.render(liquid_context, io)
    output << io.to_s

    true
  end

  private def build_simple_site_hash
    # Build collections as Array(Liquid::Any) where each element is a wrapped Hash
    collections_array = [] of Liquid::Any
    @site.collections.each do |name, collection|
      collection_hash = {} of String => Liquid::Any
      collection_hash["name"] = Liquid::Any.new(name)
      collection_hash["label"] = Liquid::Any.new(name) # Jekyll uses 'label' for collection name

      # Convert resources (called 'docs' in Jekyll) to Array(Liquid::Any)
      # Each element is a wrapped Hash(String, Liquid::Any)
      docs_as_any = [] of Liquid::Any
      collection.resources.each do |r|
        resource_hash = {} of String => Liquid::Any
        resource_hash["url"] = Liquid::Any.new(r.url.try(&.to_s) || "")
        resource_hash["title"] = Liquid::Any.new(r["title"]?.try(&.as_s) || "")
        resource_hash["content"] = Liquid::Any.new(r.content || "")
        resource_hash["excerpt"] = Liquid::Any.new(r["excerpt"]?.try(&.as_s) || "")

        # Handle categories - convert to array of Liquid::Any
        categories_value = r["categories"]?
        if categories_value.is_a?(YAML::Any) && (categories_array = categories_value.as_a?)
          resource_hash["categories"] = Liquid::Any.new(categories_array.map(&.as_s).map { |cat| Liquid::Any.new(cat) })
        else
          resource_hash["categories"] = Liquid::Any.new([] of Liquid::Any)
        end

        # Handle tags - convert to array of Liquid::Any
        tags_value = r["tags"]?
        if tags_value.is_a?(YAML::Any) && (tags_array = tags_value.as_a?)
          resource_hash["tags"] = Liquid::Any.new(tags_array.map(&.as_s).map { |tag| Liquid::Any.new(tag) })
        else
          resource_hash["tags"] = Liquid::Any.new([] of Liquid::Any)
        end

        resource_hash["header"] = Liquid::Any.new({} of String => Liquid::Any)

        # Wrap the resource hash in Liquid::Any
        docs_as_any << Liquid::Any.new(resource_hash)
      end

      # docs is Array(Liquid::Any), wrap it in Liquid::Any
      collection_hash["docs"] = Liquid::Any.new(docs_as_any)

      # Wrap the collection hash in Liquid::Any and add to collections_array
      collections_array << Liquid::Any.new(collection_hash)
    end

    # Build the final site hash with all values converted to Liquid::Any
    site_hash = {} of String => Liquid::Any
    site_hash["title"] = Liquid::Any.new(@site.config["title"]?.try(&.as_s) || "")
    site_hash["description"] = Liquid::Any.new(@site.config["description"]?.try(&.as_s) || "")
    site_hash["url"] = Liquid::Any.new(@site.config["url"]?.try(&.as_s) || "")
    site_hash["baseurl"] = Liquid::Any.new(@site.config["baseurl"]?.try(&.as_s) || "")
    site_hash["locale"] = Liquid::Any.new(@site.config["locale"]?.try(&.as_s) || "en")
    site_hash["time"] = Liquid::Any.new(Time.local.to_s)
    site_hash["collections"] = Liquid::Any.new(collections_array)

    site_hash
  end

  private def build_simple_page_hash(resource : Resource)
    page_hash = {} of String => Liquid::Any
    page_hash["url"] = Liquid::Any.new(resource.url.try(&.to_s) || "")
    page_hash["path"] = Liquid::Any.new(resource.slug || "")

    # Handle title carefully - YAML::Any might contain nil
    title_value = resource["title"]?
    title_str = if title_value
                 begin
                   title_value.as_s?
                 rescue
                   nil
                 end
               end
    page_hash["title"] = Liquid::Any.new(title_str || "")

    # Handle locale carefully
    locale_value = resource["locale"]? || @site.config["locale"]?
    locale_str = if locale_value
                  begin
                    locale_value.as_s?
                  rescue
                    nil
                  end
                end
    page_hash["locale"] = Liquid::Any.new(locale_str || "en")

    page_hash
  end

  private def build_simple_paginator_hash(resource : Resource)
    paginator_hash = {} of String => Liquid::Any

    if paginator = resource.paginator
      paginator_hash["page"] = Liquid::Any.new(paginator.page)
      paginator_hash["per_page"] = Liquid::Any.new(paginator.per_page)
      paginator_hash["total_pages"] = Liquid::Any.new(paginator.total_pages)
      paginator_hash["total_items"] = Liquid::Any.new(paginator.total_items)
    else
      paginator_hash["page"] = Liquid::Any.new(1)
      paginator_hash["per_page"] = Liquid::Any.new(0)
      paginator_hash["total_pages"] = Liquid::Any.new(1)
      paginator_hash["total_items"] = Liquid::Any.new(0)
    end

    paginator_hash
  end
end
