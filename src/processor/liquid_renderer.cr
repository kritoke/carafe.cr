require "liquid"

# Shared Liquid rendering functionality for processors.
# Handles building site/page context and rendering Liquid templates.
# Front matter is already stripped by the resource loader (Frontmatter.read_frontmatter)
# before content reaches processors, so we check for Liquid tags directly.
module Carafe::LiquidRenderer
  private alias LiquidAnyType = LiquidAny

  # Returns true if the content contains Liquid tags that need rendering
  def has_liquid_tags?(content : String) : Bool
    content.includes?("{{") || content.includes?("{%")
  end

  # Render Liquid template using site context.
  # Returns rendered content, or original source on failure.
  def render_liquid(source : String, resource : Resource, site : Site) : String
    context = LiquidContext.new
    context.set("site", LiquidAny.new(build_site_hash(site)))
    context.set("page", LiquidAny.new(build_page_hash(resource)))

    LiquidTemplate.parse(source).render(context)
  rescue ex
    STDERR.puts "ERROR rendering Liquid in #{resource.slug}: #{ex.message}"
    source
  end

  # Build site hash with config values and collections for Liquid context
  private def build_site_hash(site : Site) : Hash(String, LiquidAnyType)
    site_hash = new_liquid_any_hash

    # Standard site config values
    site_hash["title"] = LiquidAnyHelper.new_string(site.config["title"]?.try(&.as_s) || "")
    site_hash["name"] = LiquidAnyHelper.new_string(site.config["name"]?.try(&.as_s) || "")
    site_hash["description"] = LiquidAnyHelper.new_string(site.config["description"]?.try(&.as_s) || "")
    site_hash["url"] = LiquidAnyHelper.new_string(site.config["url"]?.try(&.as_s) || "")
    site_hash["baseurl"] = LiquidAnyHelper.new_string(site.config["baseurl"]?.try(&.as_s) || "")

    # Add all unmapped config values (e.g., minimal_mistakes_skin)
    site.config.yaml_unmapped.each do |k, v|
      key = k.to_s
      next if site_hash.has_key?(key)
      site_hash[key] = convert_yaml_to_liquid(v)
    end

    # Add collections (e.g., site.resources, site.posts)
    site.collections.each do |name, collection|
      resources_array = collection.resources.map do |resource|
        resource_hash = new_liquid_any_hash
        resource_hash["title"] = LiquidAnyHelper.new_string(resource["title"]?.try(&.as_s) || resource.slug)
        resource_hash["excerpt"] = LiquidAnyHelper.new_string(resource["excerpt"]?.try(&.as_s) || "")
        resource_hash["url"] = LiquidAnyHelper.new_string(resource.url.try(&.to_s) || "")
        resource_hash["path"] = LiquidAnyHelper.new_string(resource.slug || "")
        LiquidAny.new(resource_hash)
      end
      site_hash[name] = LiquidAny.new(resources_array)
    end

    # Add site.tags - hash of tag_name => [posts]
    tags_hash = new_liquid_any_hash
    site.collections.each do |name, collection|
      collection.resources.each do |resource|
        next unless resource["tags"]?
        tags_value = resource["tags"]
        tags = case raw = tags_value.raw
               when String
                 raw.split(/\s+/).map(&.strip).reject(&.empty?)
               when Array
                 raw.map { |t| t.to_s.strip }.reject(&.empty?)
               else
                 [] of String
               end
        tags.each do |tag|
          unless tags_hash.has_key?(tag)
            tags_hash[tag] = LiquidAny.new([] of LiquidAny)
          end
          arr = tags_hash[tag].raw.as(Array)
          post_hash = new_liquid_any_hash
          post_hash["title"] = LiquidAnyHelper.new_string(resource["title"]?.try(&.as_s) || resource.slug)
          post_hash["excerpt"] = LiquidAnyHelper.new_string(resource["excerpt"]?.try(&.as_s) || "")
          post_hash["url"] = LiquidAnyHelper.new_string(resource.url.try(&.to_s) || "")
          arr << LiquidAny.new(post_hash)
        end
      end
    end
    site_hash["tags"] = LiquidAny.new(tags_hash)

    site_hash
  end

  # Build page hash with resource data for Liquid context
  private def build_page_hash(resource : Resource) : Hash(String, LiquidAnyType)
    page_hash = new_liquid_any_hash
    page_hash["url"] = LiquidAnyHelper.new_string(resource.url.try(&.to_s) || "")
    page_hash["path"] = LiquidAnyHelper.new_string(resource.slug || "")
    page_hash["name"] = LiquidAnyHelper.new_string(resource.name)

    resource.frontmatter.each do |k, v|
      page_hash[k.to_s] = convert_yaml_to_liquid(v)
    end

    page_hash
  end

  # Convert YAML::Any to LiquidAnyType
  private def convert_yaml_to_liquid(value : YAML::Any) : LiquidAnyType
    case raw = value.raw
    when Hash
      hash = new_liquid_any_hash
      raw.each do |k, v|
        key = k.is_a?(String) ? k : k.to_s
        hash[key] = convert_yaml_to_liquid(v)
      end
      LiquidAny.new(hash)
    when Array
      array = raw.map { |v| convert_yaml_to_liquid(v) }
      LiquidAny.new(array)
    when String, Int32, Int64, Float64, Bool
      LiquidAny.new(raw)
    when Nil
      LiquidAny.new("")
    else
      LiquidAny.new(raw.to_s)
    end
  end

  private def new_liquid_any_hash : Hash(String, LiquidAnyType)
    {} of String => LiquidAnyType
  end
end
