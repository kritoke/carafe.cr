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
      collection.resources.each do |resource|
        resource_hash = {} of String => Liquid::Any
        resource_hash["url"] = Liquid::Any.new(resource.url.try(&.to_s) || "")
        resource_hash["title"] = Liquid::Any.new(resource["title"]?.try(&.as_s) || "")
        resource_hash["content"] = Liquid::Any.new(resource.content || "")
        resource_hash["excerpt"] = Liquid::Any.new(resource["excerpt"]?.try(&.as_s) || "")

        # Handle categories - convert to array of Liquid::Any
        categories_value = resource["categories"]?
        if categories_value.is_a?(YAML::Any) && (categories_array = categories_value.as_a?)
          resource_hash["categories"] = Liquid::Any.new(categories_array.map(&.as_s).map { |cat| Liquid::Any.new(cat) })
        else
          resource_hash["categories"] = Liquid::Any.new([] of Liquid::Any)
        end

        # Handle tags - convert to array of Liquid::Any
        tags_value = resource["tags"]?
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

    # Add direct access to each collection by name (Jekyll compatibility)
    # This allows templates to use site.posts, site.pages, site.resources, etc.
    @site.collections.each do |name, collection|
      # Convert collection resources to Array(Liquid::Any)
      docs_as_any = [] of Liquid::Any
      collection.resources.each do |resource|
        resource_hash = {} of String => Liquid::Any
        resource_hash["url"] = Liquid::Any.new(resource.url.try(&.to_s) || "")
        resource_hash["title"] = Liquid::Any.new(resource["title"]?.try(&.as_s) || "")
        resource_hash["content"] = Liquid::Any.new(resource.content || "")
        resource_hash["excerpt"] = Liquid::Any.new(resource["excerpt"]?.try(&.as_s) || "")

        # Handle categories
        categories_value = resource["categories"]?
        if categories_value.is_a?(YAML::Any) && (categories_array = categories_value.as_a?)
          resource_hash["categories"] = Liquid::Any.new(categories_array.map(&.as_s).map { |cat| Liquid::Any.new(cat) })
        else
          resource_hash["categories"] = Liquid::Any.new([] of Liquid::Any)
        end

        # Handle tags
        tags_value = resource["tags"]?
        if tags_value.is_a?(YAML::Any) && (tags_array = tags_value.as_a?)
          resource_hash["tags"] = Liquid::Any.new(tags_array.map(&.as_s).map { |tag| Liquid::Any.new(tag) })
        else
          resource_hash["tags"] = Liquid::Any.new([] of Liquid::Any)
        end

        resource_hash["header"] = Liquid::Any.new({} of String => Liquid::Any)
        docs_as_any << Liquid::Any.new(resource_hash)
      end

      # Expose collection directly by name
      site_hash[name] = Liquid::Any.new(docs_as_any)
    end

    # Build tags hash (Jekyll compatibility)
    # site.tags is an array of [tag_name, posts_array] pairs
    tags_hash = {} of String => Array(Liquid::Any)
    @site.collections.each do |collection_name, collection|
      collection.resources.each do |resource|
        tags_value = resource["tags"]?
        if tags_value.is_a?(YAML::Any)
          # Handle tags as array or string (Jekyll supports both)
          tags_list = if tags_array = tags_value.as_a?
                        tags_array.map(&.as_s)
                      elsif tags_string = tags_value.as_s?
                        # Split by comma or space
                        tags_string.split(/[,\s]+/).map(&.strip).reject(&.empty?)
                      else
                        [] of String
                      end

          # Create resource hash for this resource
          resource_hash = {} of String => Liquid::Any
          resource_hash["url"] = Liquid::Any.new(resource.url.try(&.to_s) || "")
          resource_hash["title"] = Liquid::Any.new(resource["title"]?.try(&.as_s) || "")
          resource_hash["content"] = Liquid::Any.new(resource.content || "")
          resource_hash["excerpt"] = Liquid::Any.new(resource["excerpt"]?.try(&.as_s) || "")

          # Add resource to each tag's array
          tags_list.each do |tag_name|
            tags_hash[tag_name] ||= [] of Liquid::Any
            tags_hash[tag_name] << Liquid::Any.new(resource_hash)
          end
        end
      end
    end

    # Convert tags_hash to Liquid::Any format (array of [tag_name, resources] pairs)
    tags_array = [] of Liquid::Any
    tags_hash.each do |tag_name, resources|
      tag_pair = [] of Liquid::Any
      tag_pair << Liquid::Any.new(tag_name)
      tag_pair << Liquid::Any.new(resources)
      tags_array << Liquid::Any.new(tag_pair)
    end
    site_hash["tags"] = Liquid::Any.new(tags_array)

    # Add subtitle (used in masthead)
    site_hash["subtitle"] = Liquid::Any.new(@site.config["subtitle"]?.try(&.as_s) || "")

    # Add footer (contains social media links)
    if footer_value = @site.config["footer"]?
      site_hash["footer"] = convert_yaml_any_to_liquid(footer_value)
    end

    # Add author (used in author profile)
    if author_value = @site.config["author"]?
      site_hash["author"] = convert_yaml_any_to_liquid(author_value)
    end

    # Add name (commonly used in themes)
    site_hash["name"] = Liquid::Any.new(@site.config["name"]?.try(&.as_s) || "")

    # Add email
    site_hash["email"] = Liquid::Any.new(@site.config["email"]?.try(&.as_s) || "")

    # Add minimal_mistakes_skin for theme skin selection
    site_hash["minimal_mistakes_skin"] = Liquid::Any.new(@site.config["minimal_mistakes_skin"]?.try(&.as_s) || "default")

    site_hash
  end

  # Convert YAML::Any to Liquid::Any, handling hashes and arrays recursively
  private def convert_yaml_any_to_liquid(yaml_value : YAML::Any) : Liquid::Any
    case raw = yaml_value.raw
    when Hash
      # Convert hash to Liquid::Any format
      liquid_hash = {} of String => Liquid::Any
      raw.each do |k, v|
        key_str = k.is_a?(String) ? k : k.to_s
        if v.is_a?(YAML::Any)
          liquid_hash[key_str] = convert_yaml_any_to_liquid(v)
        else
          liquid_hash[key_str] = Liquid::Any.new(v || "")
        end
      end
      Liquid::Any.new(liquid_hash)
    when Array
      # Convert array to Liquid::Any format
      liquid_array = raw.map do |item|
        if item.is_a?(YAML::Any)
          convert_yaml_any_to_liquid(item)
        else
          Liquid::Any.new(item || "")
        end
      end
      Liquid::Any.new(liquid_array)
    when String, Int32, Int64, Float64, Bool
      Liquid::Any.new(raw)
    else
      # Fallback for other types
      Liquid::Any.new(raw.to_s || "")
    end
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
