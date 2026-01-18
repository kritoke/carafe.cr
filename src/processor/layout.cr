require "liquid"
require "../processor"
require "../liquid/filters/jekyll"
require "../plugins/carafe_dark_mode"

class Carafe::Processor::Layout < Carafe::Processor
  transforms "*": "output"

  getter layouts_path : String

  getter layouts : Hash(String, {String, Frontmatter})

  getter includes_path : String

  def initialize(@site : Site = Site.new, layouts_path : String? = nil, includes_path : String? = nil)
    @layouts_path = layouts_path || File.join(site.config.source, site.config.layouts_dir)
    @includes_path = includes_path || File.join(site.config.source, site.config.includes_dir)

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

      # Set template_path in context so includes can find files
      liquid_context.set("template_path", Liquid::Any.new(@site.site_dir))

      # Set site data - deeply sanitize to ensure no nil values
      site_hash = build_site_hash
      liquid_context.set("site", sanitize_hash(site_hash))

      # Set site URL for absolute_url filter
      if site_url = @site.config["url"]?.try(&.as_s)
        Liquid::Filters::AbsoluteUrl.site_url = site_url
      end

      # Set page data - deeply sanitize
      page_hash = build_page_hash(resource)
      liquid_context.set("page", sanitize_hash(page_hash))

      # Set paginator - deeply sanitize
      paginator_hash = build_paginator_hash(resource)
      liquid_context.set("paginator", sanitize_hash(paginator_hash))

      # Set content (trim to avoid extra newlines)
      liquid_context.set("content", content.strip)

      # Set layout - deeply sanitize
      layout_hash = build_layout_hash(frontmatter)
      liquid_context.set("layout", sanitize_hash(layout_hash))

      # Set post (alias for page in Jekyll) - deeply sanitize
      liquid_context.set("post", sanitize_hash(page_hash))

      layout_name = frontmatter["layout"]?.try(&.as_s?)

      # Render the template
      begin
        template = Liquid::Template.parse(layout_template)
        # Set template_path so includes can find files relative to the site directory
        template.template_path = @site.site_dir
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

    # Inject dark mode assets if explicitly enabled via dark_mode config
    # Note: When using Minimal Mistakes with minimal_mistakes_skin set, the theme's
    # SCSS is already compiled with the appropriate colors - no class injection needed
    dark_mode_enabled = @site.config["dark_mode"]?

    should_inject_dark = !dark_mode_enabled.nil? &&
                         (dark_mode_enabled.as_s? == "true" || dark_mode_enabled.raw == true)

    if should_inject_dark
      dark_mode_html = Carafe::Plugins::CarafeDarkMode.generate_assets[:html]
      # Inject before closing </head> tag or at the end of </body>
      if content.includes?("</head>")
        content = content.gsub("</head>", "#{dark_mode_html}\n</head>")
      elsif content.includes?("</body>")
        content = content.gsub("</body>", "#{dark_mode_html}\n</body>")
      else
        content += dark_mode_html
      end
    end

    # Ensure output always ends with exactly one newline
    trimmed = content.rstrip
    output << trimmed
    output << "\n"
    true
  end

  # Process Jekyll-style includes by reading the file and inserting its content
  # Supports: {% include file.html %} and {% include file.html param=value %}
  # Recursively processes nested includes
  # NOTE: Includes with parameters (e.g., {% include file.html param=value %})
  # are NOT processed here - they are handled by the JekyllInclude tag during
  # Liquid rendering to properly support parameter passing.
  private def process_includes(template : String, resource : Resource) : String
    includes_dir = @includes_path
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

        # Check if this include has parameters (contains "=" after whitespace)
        # If so, skip processing it here - let JekyllInclude handle it
        if include_content =~ /\s+[A-Za-z_]\w*=/
          # Return the original include tag unchanged
          "{% include #{include_content}%}"
        else
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
            include_content = File.read(include_path).rstrip

            # Remove self-referential includes to prevent infinite loops
            # If toc.html contains "{% include toc.html %}", remove it
            include_content = include_content.gsub(/{%\s*include\s+#{Regex.escape(file)}\b[^%]*%}/, "<!-- Self-include removed: #{file} -->")

            # Preprocess to remove Jekyll-specific for loop modifiers that Liquid doesn't support
            include_content = preprocess_jekyll_syntax(include_content)

            include_content
          else
            # If file not found, replace with empty comment to avoid Liquid parse errors
            "<!-- Include not found: #{file} -->"
          end
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
  # - where_exp, sort, and reverse filters (not supported by Liquid)
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

    # Remove where_exp, sort, and reverse filters from assign statements
    # These filters are not supported by Liquid, but we already sort posts correctly
    # in build_site_hash, so removing them is safe
    # IMPORTANT: Must preserve the closing %} or the assign statement will be invalid
    template = template.gsub(/\|\s*where_exp:\s*"[^"]*"\s*,\s*"[^"]*"(\s*%})/, "\\1")
    template = template.gsub(/\|\s*sort:\s*"[^"]*"(\s*%})/, "\\1")
    template = template.gsub(/\|\s*reverse(\s*%})/, "\\1")

    # Clean up any double pipes
    template = template.gsub(/\|\s*\|/, "|")

    # Clean up trailing pipes before closing brace (but only if there's nothing after the pipe)
    # Pattern: | %}  or  | %}
    template = template.gsub(/\|\s*(%})/, "\\1")

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
    site_hash["name"] = Liquid::Any.new(@site.config["name"]?.try(&.as_s) || @site.config["title"]?.try(&.as_s) || "Site")
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
      collection.resources.each do |resource|
        doc_hash = {} of String => Liquid::Any
        doc_hash["url"] = Liquid::Any.new(resource.url.try(&.to_s) || "")
        doc_hash["title"] = Liquid::Any.new(resource["title"]?.try(&.as_s) || "")
        docs_array << Liquid::Any.new(doc_hash)
      end
      collection_hash["docs"] = Liquid::Any.new(docs_array)

      collections_array << Liquid::Any.new(collection_hash)
    end

    # Convert collections array to hash for Jekyll compatibility
    # In Jekyll, site.collections.collection_name works
    collections_hash = {} of String => Liquid::Any
    collections_array.each do |collection_any|
      collection = collection_any.raw.as(Hash(String, Liquid::Any))
      collection_name = collection["name"].as_s
      collections_hash[collection_name] = collection_any
    end
    site_hash["collections"] = Liquid::Any.new(collections_hash)

    # Aggregate tags from all resources across all collections
    tags_hash = Hash(String, Array(Liquid::Any)).new
    @site.collections.each do |name, collection|
      collection.resources.each do |resource|
        # Get tags from resource frontmatter
        if tags_value = resource["tags"]?
          # Convert resource to Liquid::Any hash
          resource_hash = {} of String => Liquid::Any
          resource_hash["url"] = Liquid::Any.new(resource.url.try(&.to_s) || "")
          resource_hash["title"] = Liquid::Any.new(resource["title"]?.try(&.as_s) || "")
          resource_hash["date"] = Liquid::Any.new(resource.date.to_s)
          resource_hash["slug"] = Liquid::Any.new(resource.slug)
          resource_hash["collection"] = Liquid::Any.new(name)

          # Handle tags as array or string (Jekyll supports both)
          tags_list = if tags_value.is_a?(YAML::Any)
                        if tags_array = tags_value.as_a?
                          tags_array.map(&.as_s)
                        elsif tags_string = tags_value.as_s?
                          # Split by comma or space
                          tags_string.split(/[,\s]+/).map(&.strip).reject(&.empty?)
                        else
                          [] of String
                        end
                      else
                        [] of String
                      end

          # Add resource to each tag's array
          tags_list.each do |tag_name|
            tags_hash[tag_name] ||= [] of Liquid::Any
            tags_hash[tag_name] << Liquid::Any.new(resource_hash)
          end
        end
      end
    end

    # Convert tags_hash to Liquid::Any format
    # Jekyll's site.tags is an array of [tag_name, posts_array] pairs, not a hash
    tags_array = [] of Liquid::Any
    tags_hash.each do |tag_name, resources|
      # Create [tag_name, resources] pair as Liquid::Any array
      tag_pair = [] of Liquid::Any
      tag_pair << Liquid::Any.new(tag_name)
      tag_pair << Liquid::Any.new(resources)
      tags_array << Liquid::Any.new(tag_pair)
    end
    site_hash["tags"] = Liquid::Any.new(tags_array)

    # Add posts collection as site.posts (Jekyll compatibility)
    # site.posts is an alias for the 'posts' collection resources in reverse chronological order
    posts_array = [] of Liquid::Any
    if posts_collection = @site.collections["posts"]?
      # Sort posts by date (newest first)
      sorted_posts = posts_collection.resources.sort_by(&.date).reverse!

      sorted_posts.each do |post|
        post_hash = {} of String => Liquid::Any
        post_hash["url"] = Liquid::Any.new(post.url.try(&.to_s) || "")
        post_hash["title"] = Liquid::Any.new(post["title"]?.try(&.as_s) || "")
        post_hash["date"] = Liquid::Any.new(post.date.to_s)
        post_hash["slug"] = Liquid::Any.new(post.slug)
        post_hash["excerpt"] = Liquid::Any.new(post["excerpt"]?.try(&.as_s) || "")
        post_hash["content"] = Liquid::Any.new(post.content || "")

        # Add all frontmatter data
        post.frontmatter.each do |k, v|
          post_hash[k.to_s] = convert_yaml_to_liquid(v)
        end

        posts_array << Liquid::Any.new(post_hash)
      end
    end
    site_hash["posts"] = Liquid::Any.new(posts_array)

    # Add subtitle (used in masthead)
    site_hash["subtitle"] = Liquid::Any.new(@site.config["subtitle"]?.try(&.as_s) || "")

    # Add footer (contains social media links)
    if footer_value = @site.config["footer"]?
      site_hash["footer"] = convert_yaml_to_liquid(footer_value)
    end

    # Add author (used in author profile)
    if author_value = @site.config["author"]?
      site_hash["author"] = convert_yaml_to_liquid(author_value)
    end

    # Add email
    site_hash["email"] = Liquid::Any.new(@site.config["email"]?.try(&.as_s) || "")

    # Add search configuration (for Minimal Mistakes theme search button)
    site_hash["search"] = Liquid::Any.new(@site.config["search"]?.try(&.as_bool?) || false)
    if search_provider = @site.config["search_provider"]?.try(&.as_s)
      site_hash["search_provider"] = Liquid::Any.new(search_provider)
    end

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
      when Nil
        # Skip nil values entirely - they shouldn't be in the config
      when Hash
        # Convert nested hashes
        hash = {} of String => Liquid::Any
        raw.each do |yaml_key, yaml_value|
          hash_key = yaml_key.is_a?(String) ? yaml_key : yaml_key.to_s
          # Recursively convert nested values
          if yaml_value.is_a?(YAML::Any)
            hash[hash_key] = convert_yaml_to_liquid(yaml_value)
          elsif yaml_value.nil?
            hash[hash_key] = Liquid::Any.new("")
          else
            hash[hash_key] = Liquid::Any.new(yaml_value.to_s)
          end
        end
        config_hash[key] = Liquid::Any.new(hash)
      when Array
        # Convert arrays
        array = raw.map do |item|
          if item.is_a?(YAML::Any)
            convert_yaml_to_liquid(item)
          elsif item.nil?
            Liquid::Any.new("")
          else
            Liquid::Any.new(item.to_s)
          end
        end
        config_hash[key] = Liquid::Any.new(array)
      else
        # Convert any other type to string
        config_hash[key] = Liquid::Any.new(raw.to_s)
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

    # Add page name (filename)
    page_hash["name"] = Liquid::Any.new(resource.name)

    # For index.html files, normalize the URL to "/"
    if url.ends_with?("/index.html") || url == "/index.html"
      url = "/"
    end

    page_hash["url"] = Liquid::Any.new(url)
    page_hash["path"] = Liquid::Any.new(path)
    # Only add date for posts, not pages
    # Posts collection resources always get a date (even if inferred from filename)
    # Other pages only get a date if explicitly set in frontmatter
    collection_name = resource.collection.try(&.name)
    # DEBUG: Uncomment to see collection names
    # STDERR.puts "DEBUG: resource=#{resource.slug}, collection=#{collection_name.inspect}, has_date=#{resource.frontmatter.has_key?("date")}"
    if collection_name == "posts" || resource.frontmatter.has_key?("date")
      page_hash["date"] = Liquid::Any.new(resource.date.to_s)
    end

    # Add frontmatter data (overrides defaults)
    resource.frontmatter.each do |k, v|
      page_hash[k.to_s] = convert_yaml_to_liquid(v)
    end

    # Ensure layout is set (check defaults if not in frontmatter)
    unless page_hash.has_key?("layout")
      if layout_value = resource["layout"]?
        page_hash["layout"] = Liquid::Any.new(layout_value.as_s)
      end
    end

    # Add TOC if it was generated by the markdown processor
    if toc_value = resource["toc"]?
      toc_string = toc_value.as_s
      page_hash["toc"] = Liquid::Any.new(toc_string) unless toc_string.empty?
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
    when String, Int32, Int64, Float64, Bool
      Liquid::Any.new(raw)
    when Nil
      # Convert nil to empty string to avoid type cast errors in templates
      Liquid::Any.new("")
    else
      Liquid::Any.new(raw.to_s)
    end
  end

  # Deeply sanitize a Hash(String, Liquid::Any) to ensure no nested nil values
  # This is necessary because build_page_hash and other methods might create
  # nested structures that still contain nil values
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
