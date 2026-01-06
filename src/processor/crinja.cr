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

    # Set site data - deeply sanitize to ensure no nil values
    site_hash = build_simple_site_hash()
    liquid_context.set("site", sanitize_hash(site_hash))

    # Set page data - deeply sanitize
    page_hash = build_simple_page_hash(resource)
    liquid_context.set("page", sanitize_hash(page_hash))

    # Set paginator data - deeply sanitize
    paginator_hash = build_simple_paginator_hash(resource)
    liquid_context.set("paginator", sanitize_hash(paginator_hash))

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

  # Deeply sanitize a Hash(String, Liquid::Any) to ensure no nested nil values
  private def sanitize_hash(hash : Hash(String, Liquid::Any)) : Hash(String, Liquid::Any)
    sanitized = {} of String => Liquid::Any

    hash.each do |key, value|
      case raw = value.raw
      when Nil
        # Replace nil with empty string
        sanitized[key] = Liquid::Any.new("")
      when Hash
        # Recursively sanitize nested hashes
        nested = {} of String => Liquid::Any
        raw.each do |k, v|
          key_str = k.is_a?(String) ? k : k.to_s
          if v.is_a?(Liquid::Any)
            # Recursively sanitize
            temp_hash = {key_str => v}
            temp_sanitized = sanitize_hash(temp_hash)
            nested[key_str] = temp_sanitized[key_str]
          elsif v.nil?
            nested[key_str] = Liquid::Any.new("")
          else
            nested[key_str] = Liquid::Any.new(v)
          end
        end
        sanitized[key] = Liquid::Any.new(nested)
      when Array
        # Sanitize arrays
        sanitized_array = raw.map do |item|
          if item.is_a?(Liquid::Any)
            item_raw = item.raw
            if item_raw.nil?
              Liquid::Any.new("")
            elsif item_raw.is_a?(Hash)
              # Convert hash to sanitized hash
              temp_hash = {} of String => Liquid::Any
              item_raw.each do |k, v|
                key_str = k.is_a?(String) ? k : k.to_s
                temp_hash[key_str] = v.is_a?(Liquid::Any) ? v : Liquid::Any.new(v || "")
              end
              Liquid::Any.new(temp_hash)
            else
              item
            end
          elsif item.nil?
            Liquid::Any.new("")
          else
            Liquid::Any.new(item)
          end
        end
        sanitized[key] = Liquid::Any.new(sanitized_array)
      else
        sanitized[key] = value
      end
    end

    sanitized
  end
end
