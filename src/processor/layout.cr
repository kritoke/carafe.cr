require "liquid"
require "../processor"

class Carafe::Processor::Layout < Carafe::Processor
  transforms "*": "output"

  getter layouts_path : String

  getter layouts : Hash(String, {String, Frontmatter})

  def initialize(@site : Site = Site.new, layouts_path : String? = nil, includes_path : String? = nil)
    @layouts_path = layouts_path || File.join(site.config.source, site.config.layouts_dir)
    # includes_path is kept for API compatibility but not used in Liquid implementation
    _ = includes_path

    @layouts = Hash(String, {String, Frontmatter}).new do |hash, key|
      hash[key] = load_layout(key)
    end
  end

  def process(resource : Resource, input : IO, output : IO) : Bool
    layout_name = resource["layout"]?.try &.as_s?

    if !layout_name || layout_name == "none"
      return false
    end

    # Skip layout processing for non-HTML files (CSS, SASS, JS, etc.)
    # These files might have layout defaults set, but they shouldn't be processed as templates
    ext = File.extname(resource.slug || "")
    if ext == ".css" || ext == ".scss" || ext == ".sass" || ext == ".js"
      return false
    end

    content = input.gets_to_end

    loop do
      layout_template, frontmatter = layouts[layout_name.to_s]

      # Process includes manually - replace {% include file.html %} with file content
      # This bypasses the Liquid shard's broken include syntax
      layout_template = process_includes(layout_template, resource)

      # Preprocess the layout template to remove Jekyll-specific syntax
      layout_template = preprocess_jekyll_syntax(layout_template)

      # Build Liquid context with site data
      liquid_context = Liquid::Context.new

      # Set site data
      liquid_context.set("site", build_site_hash)

      # Set page data
      liquid_context.set("page", build_page_hash(resource))

      # Set paginator
      liquid_context.set("paginator", build_paginator_hash(resource))

      # Set content
      liquid_context.set("content", content)

      # Set layout
      liquid_context.set("layout", build_layout_hash(frontmatter))

      # Set post (alias for page in Jekyll)
      liquid_context.set("post", build_page_hash(resource))

      layout_name = frontmatter["layout"]?.try(&.as_s?)

      # Render the template
      begin
        # Check if there are any remaining include tags
        remaining_includes = layout_template.scan(/{%\s*include\s+[^%]+?%}/)
        if remaining_includes.size > 0
          STDERR.puts "ERROR: #{remaining_includes.size} include tags remain after preprocessing:"
          remaining_includes.each do |match|
            STDERR.puts "  #{match[0]}"
          end
        end

        template = Liquid::Template.parse(layout_template)
        content = template.render(liquid_context)
      rescue ex
        STDERR.puts "ERROR rendering layout #{layout_name}:"
        STDERR.puts ex.message
        STDERR.puts ex.backtrace.join("\n")
        raise ex
      end

      if !layout_name || layout_name == "none"
        break
      end
    end

    output << content
    output << "\n"
    true
  end

  # Process Jekyll-style includes by reading the file and inserting its content
  # Supports: {% include file.html %} and {% include file.html param=value %}
  # Recursively processes nested includes
  private def process_includes(template : String, resource : Resource) : String
    includes_dir = File.join(@site.site_dir, @site.config.includes_dir)
    max_iterations = 100 # Prevent infinite loops
    iteration = 0

    # Keep processing until no more include tags are found
    while template.includes?("{% include") && iteration < max_iterations
      iteration += 1

      # Match include tags - capture everything from "include" to "%}"
      # Then extract the filename (first word after "include")
      match_count_before = template.scan(/{%\s*include\s+[^%]+?%}/).size
      template = template.gsub(/{%\s*include\s+([^%]+?)%}/) do |_match|
        include_content = $1
        # Extract just the filename (first word, before any space or parameter)
        # Handle quoted filenames and filenames with paths
        file = include_content.split(/\s+/).first

        # Remove quotes if present
        file = file.delete('"')

        # Remove leading slash if present (e.g., /comments-providers/disqus.html)
        file = file.lstrip('/')

        # Try to find the include file
        # Check in site's _includes directory
        include_path = File.join(includes_dir, file)

        # Also check in theme's _includes directory
        unless File.exists?(include_path)
          theme_dir = @site.config["theme_dir"]?.try(&.as_s?)
          if theme_dir
            theme_include_path = File.join(theme_dir, "_includes", file)
            include_path = theme_include_path if File.exists?(theme_include_path)
          end
        end

        if File.exists?(include_path)
          # Read and return the file content
          # This content may contain more includes, which will be processed in the next iteration
          include_content = File.read(include_path)

          # Remove self-referential includes to prevent infinite loops
          # If toc.html contains "{% include toc.html %}", remove it
          include_content = include_content.gsub(/{%\s*include\s+#{Regex.escape(file)}\b[^%]*%}/, "<!-- Self-include removed: #{file} -->")

          # Preprocess to remove Jekyll-specific for loop modifiers that Liquid doesn't support
          include_content = preprocess_jekyll_syntax(include_content)

          # Debug: check if limit: still exists after preprocessing
          if include_content.includes?("limit:")
            STDERR.puts "DEBUG: After preprocessing #{file}, still contains 'limit:'"
          end

          include_content
        else
          # If file not found, replace with empty comment to avoid Liquid parse errors
          STDERR.puts "DEBUG: Include file not found: #{file} (tried: #{include_path})"
          "<!-- Include not found: #{file} -->"
        end
      end
      match_count_after = template.scan(/{%\s*include\s+[^%]+?%}/).size

      if match_count_before > 0 && match_count_after == match_count_before
        STDERR.puts "WARNING: process_includes iteration #{iteration}: #{match_count_before} includes found, but none were processed"
        break
      end
    end

    template
  end

  # Preprocess Jekyll-specific Liquid syntax that the Liquid shard doesn't support
  # Currently handles:
  # - for loop modifiers: offset, limit, reversed
  # - for loops with variable ranges (not supported by Liquid)
  # - {% continue %} tag (not supported by Liquid)
  private def preprocess_jekyll_syntax(template : String) : String

    # Remove Jekyll for loop modifiers
    # Jekyll: {% for item in array offset: 1 limit: 5 %}
    # Liquid: {% for item in array %} (modifiers not supported)
    original_template = template
    template = template.gsub(/({%\s*for\s+\w+\s+in\s+\w+)(\s+offset:\s*\d+)?(\s+limit:\s*\d+)?(\s+reversed)?(\s*%})/) do |_match|
      for_start = $1
      _offset = $2?
      _limit = $3?
      _reversed = $4?
      for_end = $5

      # For now, just remove the modifiers entirely
      # A complete implementation would actually apply these modifiers
      "#{for_start}#{for_end}"
    end

    if template != original_template && template.includes?("limit:")
      STDERR.puts "WARNING: preprocess_jekyll_syntax failed to remove all limit modifiers"
    end

    # Replace for loops with variable ranges with a fixed range (1..1)
    # Jekyll: {% for i in (page_start..page_end) %}...{% endfor %}
    # Liquid doesn't support variable ranges, only literals like {% for i in (1..5) %}
    # We replace the variable range with (1..1) which will iterate once
    template = template.gsub(/({%\s*for\s+\w+\s+in\s+)\([^)]+\.\.[^)]+\)(\s*%})/) do |_match|
      "#{$1}(1..1)#{$2}"
    end

    # Remove orphaned endfor tags that might be left after removing for loops
    # This is a simple approach - a more sophisticated solution would track pairs
    template = template.gsub(/({%\s*endfor\s*%})/) do |_match|
      # Count for loops vs endfor tags before this replacement
      for_count = template.scan(/{%\s*for\s/).size
      endfor_count = template.scan(/{%\s*endfor\s*%}/).size
      if endfor_count > for_count
        "" # Remove excess endfor tags
      else
        "{% endfor %}" # Keep balanced endfor tags
      end
    end

    # Remove {% continue %} tags (not supported by Liquid)
    template = template.gsub(/{%\s*continue\s*%}/, "")

    template
  end

  # Convert Jekyll include syntax to Liquid-compatible syntax
  # Jekyll: {% include file.html param=value other=foo %}
  # Jekyll: {% include file.html %}
  # Liquid: {% include "file.html", param: value, other: foo %}
  # Liquid: {% include "file.html" %}
  private def convert_jekyll_includes(template : String) : String
    # First, handle includes with parameters
    template = template.gsub(/{%\s*include\s+(\S+?)\s+([^}%]+?)\s*%}/) do |_match|
      file = $1
      params = $2

      # Add quotes around filename if not already quoted
      quoted_file = file.starts_with?('"') ? file : "\"#{file}\""

      # Convert param=value to param: value, and add commas
      liquid_params = params.gsub(/(\w+)=(\S+)/, "\\1: \\2").gsub(" ", ", ")

      "{% include #{quoted_file}, #{liquid_params} %}"
    end

    # Then, handle includes without parameters
    template.gsub(/{%\s*include\s+(\S+?)\s*%}/) do |_match|
      file = $1

      # Add quotes around filename if not already quoted
      quoted_file = file.starts_with?('"') ? file : "\"#{file}\""

      "{% include #{quoted_file} %}"
    end
  end

  def load_layout(layout_name : String) : {String, Frontmatter}
    file_pattern = File.join(File.expand_path(layouts_path, @site.site_dir), "#{layout_name}.*")
    file_path = Dir[file_pattern].first?

    raise "Layout not found: #{layout_name.inspect} (layouts_path: #{layouts_path}) at #{file_pattern}" unless file_path

    File.open(file_path) do |file|
      frontmatter = Frontmatter.read_frontmatter(file) || Frontmatter.new
      content = file.gets_to_end

      return content, frontmatter
    end
  end

  private def build_site_hash : Hash(String, Liquid::Any)
    site_hash = {} of String => Liquid::Any

    # Basic site config
    site_hash["config"] = build_config_hash
    site_hash["data"] = build_data_hash
    site_hash["locale"] = Liquid::Any.new(@site.config["locale"]?.try(&.as_s) || "en")
    site_hash["title"] = Liquid::Any.new(@site.config["title"]?.try(&.as_s) || "Site")
    site_hash["title_separator"] = Liquid::Any.new(@site.config["title_separator"]?.try(&.as_s) || "|")
    site_hash["baseurl"] = Liquid::Any.new(@site.config["baseurl"]?.try(&.as_s) || "")
    site_hash["url"] = Liquid::Any.new(@site.config["url"]?.try(&.as_s) || "")
    site_hash["time"] = Liquid::Any.new(Time.local.to_s)

    # Add collections (for site.collections iteration)
    collections_array = [] of Liquid::Any
    @site.collections.each do |name, collection|
      collection_hash = {} of String => Liquid::Any
      collection_hash["name"] = Liquid::Any.new(name)
      collection_hash["label"] = Liquid::Any.new(name)
      collection_hash["output"] = Liquid::Any.new(collection.defaults.output?)

      # Convert resources to array
      docs_array = [] of Liquid::Any
      collection.resources.each do |r|
        doc_hash = {} of String => Liquid::Any
        doc_hash["url"] = Liquid::Any.new(r.url.try(&.to_s) || "")
        doc_hash["title"] = Liquid::Any.new(r["title"]?.try(&.as_s) || "")
        docs_array << Liquid::Any.new(doc_hash)
      end
      collection_hash["docs"] = Liquid::Any.new(docs_array)

      collections_array << Liquid::Any.new(collection_hash)
    end
    site_hash["collections"] = Liquid::Any.new(collections_array)

    site_hash
  end

  private def build_config_hash : Liquid::Any
    config_hash = {} of String => Liquid::Any

    # Add common config values that are frequently accessed
    config_hash["source"] = Liquid::Any.new(@site.config.source)
    config_hash["destination"] = Liquid::Any.new(@site.config.destination)
    config_hash["collections_dir"] = Liquid::Any.new(@site.config.collections_dir)
    config_hash["layouts_dir"] = Liquid::Any.new(@site.config.layouts_dir)
    config_hash["data_dir"] = Liquid::Any.new(@site.config.data_dir)
    config_hash["includes_dir"] = Liquid::Any.new(@site.config.includes_dir)
    config_hash["port"] = Liquid::Any.new(@site.config.port)
    config_hash["host"] = Liquid::Any.new(@site.config.host)
    config_hash["baseurl"] = Liquid::Any.new(@site.config.baseurl)
    config_hash["paginate_path"] = Liquid::Any.new(@site.config.paginate_path)

    # Add any unmapped YAML config values
    @site.config.yaml_unmapped.each do |k, v|
      key = k.to_s
      next if config_hash.has_key?(key)

      case raw = v.raw
      when String
        config_hash[key] = Liquid::Any.new(raw)
      when Int32, Int64, Float64, Bool
        config_hash[key] = Liquid::Any.new(raw)
      end
    end

    Liquid::Any.new(config_hash)
  end

  private def build_data_hash : Liquid::Any
    data_hash = {} of String => Liquid::Any

    @site.data.each do |key, value|
      data_hash[key] = convert_yaml_to_liquid(value)
    end

    # Add default for ui-text if not present
    data_hash["ui-text"] ||= Liquid::Any.new({} of String => Liquid::Any)

    Liquid::Any.new(data_hash)
  end

  private def build_page_hash(resource : Resource) : Hash(String, Liquid::Any)
    page_hash = {} of String => Liquid::Any

    # Get URL from resource
    url = resource.url.try(&.to_s) || ""
    path = resource.slug || ""

    page_hash["url"] = Liquid::Any.new(url)
    page_hash["path"] = Liquid::Any.new(path)
    page_hash["date"] = Liquid::Any.new(resource.date.to_s)

    # Add frontmatter data
    resource.frontmatter.each do |k, v|
      page_hash[k.to_s] = convert_yaml_to_liquid(v)
    end

    # Ensure defaults
    page_hash["authors"] ||= Liquid::Any.new([] of Liquid::Any)
    page_hash["author"] ||= Liquid::Any.new("")
    page_hash["excerpt"] ||= Liquid::Any.new("")
    page_hash["locale"] ||= Liquid::Any.new(@site.config["locale"]?.try(&.as_s) || "en")

    page_hash
  end

  private def build_paginator_hash(resource : Resource) : Hash(String, Liquid::Any)
    paginator_hash = {} of String => Liquid::Any

    if paginator = resource.paginator
      paginator_hash["page"] = Liquid::Any.new(paginator.page)
      paginator_hash["per_page"] = Liquid::Any.new(paginator.per_page)
      paginator_hash["total_pages"] = Liquid::Any.new(paginator.total_pages)
      paginator_hash["total_items"] = Liquid::Any.new(paginator.total_items)
      paginator_hash["previous_page"] = Liquid::Any.new(paginator.previous_page)
      paginator_hash["previous_page_path"] = Liquid::Any.new(paginator.previous_page_path)
      paginator_hash["next_page"] = Liquid::Any.new(paginator.next_page)
      paginator_hash["next_page_path"] = Liquid::Any.new(paginator.next_page_path)

      # Add posts (alias for items) for Jekyll compatibility
      posts_array = [] of Liquid::Any
      paginator.items.each do |item|
        post_hash = {} of String => Liquid::Any
        post_hash["url"] = Liquid::Any.new(item.url.try(&.to_s) || "")
        post_hash["title"] = Liquid::Any.new(item["title"]?.try(&.as_s) || "")

        # Add all frontmatter data
        item.frontmatter.each do |k, v|
          post_hash[k.to_s] = convert_yaml_to_liquid(v)
        end

        posts_array << Liquid::Any.new(post_hash)
      end
      paginator_hash["posts"] = Liquid::Any.new(posts_array)
    else
      # Default paginator
      paginator_hash["page"] = Liquid::Any.new(1)
      paginator_hash["per_page"] = Liquid::Any.new(0)
      paginator_hash["total_pages"] = Liquid::Any.new(1)
      paginator_hash["total_items"] = Liquid::Any.new(0)
      paginator_hash["previous_page"] = Liquid::Any.new(nil)
      paginator_hash["previous_page_path"] = Liquid::Any.new("")
      paginator_hash["next_page"] = Liquid::Any.new(nil)
      paginator_hash["next_page_path"] = Liquid::Any.new("")
      paginator_hash["posts"] = Liquid::Any.new([] of Liquid::Any)
    end

    paginator_hash
  end

  private def build_layout_hash(frontmatter : Frontmatter) : Hash(String, Liquid::Any)
    layout_hash = {} of String => Liquid::Any

    frontmatter.each do |k, v|
      layout_hash[k.to_s] = convert_yaml_to_liquid(v)
    end

    layout_hash
  end

  private def convert_yaml_to_liquid(value : YAML::Any) : Liquid::Any
    case raw = value.raw
    when Hash
      hash = {} of String => Liquid::Any
      raw.each do |k, v|
        key = k.is_a?(String) ? k : k.to_s
        hash[key] = convert_yaml_to_liquid(v)
      end
      Liquid::Any.new(hash)
    when Array
      array = raw.map { |v| convert_yaml_to_liquid(v) }
      Liquid::Any.new(array)
    when String, Int32, Int64, Float64, Bool, Nil
      Liquid::Any.new(raw)
    else
      Liquid::Any.new(raw.to_s)
    end
  end
end
