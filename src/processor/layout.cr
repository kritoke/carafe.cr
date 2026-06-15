require "liquid"
require "../processor"
require "../jekyll_compat"
require "../plugins/content/dark_mode"
require "../util/security"

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
    return false if should_skip_processing?(resource)

    content = input.gets_to_end

    loop do
      layout_template, frontmatter = layouts[layout_name.to_s]

      layout_template = process_includes(layout_template, resource)
      layout_template = JekyllCompat::Preprocessor.preprocess(layout_template)

      liquid_context = build_liquid_context(resource, content.strip, frontmatter)

      layout_name = frontmatter["layout"]?.try(&.as_s?)

      begin
        template = LiquidTemplate.parse(layout_template)
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

    content = inject_dark_mode_assets(content)

    trimmed = content.rstrip
    output << trimmed
    output << "\n"
    true
  end

  private def process_includes(template : String, resource : Resource) : String
    ctx = JekyllCompat::IncludeContext.new(
      includes_path: @includes_path,
      site_path: @site.site_dir,
      theme_dir: @site.config["theme_dir"]?.try(&.as_s)
    )
    JekyllCompat::IncludeHandler.process(template, ctx)
  end

  private def should_skip_processing?(resource : Resource) : Bool
    layout_name = resource["layout"]?.try &.as_s?
    return true if !layout_name || layout_name == "none"

    ext = File.extname(resource.slug || "")
    ext == ".css" || ext == ".scss" || ext == ".sass" || ext == ".js"
  end

  def load_layout(layout_name : String) : {String, Frontmatter}
    # Security: Sanitize the layout name to prevent path traversal
    safe_name = Security.sanitize_filename(layout_name)
    raise "Invalid layout name" if safe_name.nil?

    layouts_root = File.expand_path(layouts_path, @site.site_dir)
    layouts_root = layouts_root.gsub("\\", "/")

    # Find a direct child with a supported extension (reject symlinks)
    file_path = find_layout_file(layouts_root, safe_name)

    raise "Layout not found: #{layout_name.inspect} (layouts_path: #{layouts_path})" unless file_path

    # Final security validation
    resolved = File.expand_path(file_path)
    resolved = resolved.gsub("\\", "/")
    unless resolved.starts_with?(layouts_root + "/")
      raise "Layout path traversal detected"
    end

    File.open(file_path) do |file|
      frontmatter = Frontmatter.read_frontmatter(file) || Frontmatter.new
      content = file.gets_to_end
      return content, frontmatter
    end
  end

  private def find_layout_file(layouts_root : String, safe_name : String) : String?
    [".html", ".liquid", ".md"].each do |ext|
      path = File.join(layouts_root, "#{safe_name}#{ext}")
      return path if File.exists?(path) && !File.symlink?(path)
    end
    nil
  end

  private def inject_dark_mode_assets(content : String) : String
    dark_mode_enabled = @site.config["dark_mode"]?
    should_inject_dark = !dark_mode_enabled.nil? &&
                         (dark_mode_enabled.as_s? == "true" || dark_mode_enabled.raw == true)

    if should_inject_dark
      dark_mode_html = Carafe::Plugins::DarkMode.generate_assets[:html]
      if content.includes?("</head>")
        content.gsub("</head>", "#{dark_mode_html}\n</head>")
      elsif content.includes?("</body>")
        content.gsub("</body>", "#{dark_mode_html}\n</body>")
      else
        content + dark_mode_html
      end
    else
      content
    end
  end

  private def build_liquid_context(resource : Resource, content : String, frontmatter : Frontmatter) : LiquidContext
    liquid_context = LiquidContext.new
    liquid_context.set("template_path", LiquidAny.new(@site.site_dir))

    site_hash = build_site_hash
    liquid_context.set("site", sanitize_hash(site_hash))

    if site_url = @site.config["url"]?.try(&.as_s)
      JekyllCompat::LiquidFilters.site_url = site_url
    end

    if baseurl = @site.config.baseurl
      JekyllCompat::LiquidFilters.baseurl = baseurl
    end

    page_hash = build_page_hash(resource)
    liquid_context.set("page", sanitize_hash(page_hash))

    paginator_hash = build_paginator_hash(resource)
    liquid_context.set("paginator", sanitize_hash(paginator_hash))

    liquid_context.set("content", content)

    layout_hash = build_layout_hash(frontmatter)
    liquid_context.set("layout", sanitize_hash(layout_hash))

    liquid_context.set("post", sanitize_hash(page_hash))
    liquid_context
  end

  private def build_site_hash : Hash(String, LiquidAny)
    site_hash = build_basic_site_config
    site_hash["collections"] = build_collections_hash
    site_hash["tags"] = build_tags_hash
    site_hash["posts"] = build_posts_hash
    add_optional_fields(site_hash)
    site_hash
  end

  private def build_basic_site_config : Hash(String, LiquidAny)
    site_hash = {} of String => LiquidAny
    site_hash["config"] = build_config_hash
    site_hash["data"] = build_data_hash
    site_hash["locale"] = LiquidAny.new(@site.config["locale"]?.try(&.as_s) || "en")
    site_hash["title"] = LiquidAny.new(@site.config["title"]?.try(&.as_s) || "Site")
    site_hash["name"] = LiquidAny.new(@site.config["name"]?.try(&.as_s) || @site.config["title"]?.try(&.as_s) || "Site")
    site_hash["title_separator"] = LiquidAny.new(@site.config["title_separator"]?.try(&.as_s) || "|")
    site_hash["baseurl"] = LiquidAny.new(@site.config["baseurl"]?.try(&.as_s) || "")
    site_hash["url"] = LiquidAny.new(@site.config["url"]?.try(&.as_s) || "")
    site_hash["description"] = LiquidAny.new(@site.config["description"]?.try(&.as_s) || "")
    site_hash["time"] = LiquidAny.new(Time.local.to_s)
    site_hash
  end

  private def add_optional_fields(site_hash : Hash(String, LiquidAny)) : Nil
    site_hash["subtitle"] = LiquidAny.new(@site.config["subtitle"]?.try(&.as_s) || "")

    if footer_value = @site.config["footer"]?
      site_hash["footer"] = convert_yaml_to_liquid(footer_value)
    end

    if author_value = @site.config["author"]?
      site_hash["author"] = convert_yaml_to_liquid(author_value)
    end

    site_hash["email"] = LiquidAny.new(@site.config["email"]?.try(&.as_s) || "")

    site_hash["search"] = LiquidAny.new(@site.config["search"]?.try(&.as_bool?) || false)
    if search_provider = @site.config["search_provider"]?.try(&.as_s)
      site_hash["search_provider"] = LiquidAny.new(search_provider)
    end

    # Add twitter config
    if twitter_value = @site.config["twitter"]?
      site_hash["twitter"] = convert_yaml_to_liquid(twitter_value)
    end

    # Add social config
    if social_value = @site.config["social"]?
      site_hash["social"] = convert_yaml_to_liquid(social_value)
    end

    # Add og_image if present
    if og_image = @site.config["og_image"]?.try(&.as_s)
      site_hash["og_image"] = LiquidAny.new(og_image)
    end
  end

  private def build_collections_hash : LiquidAny
    collections_array = [] of LiquidAny
    @site.collections.each do |name, collection|
      collection_hash = {} of String => LiquidAny
      collection_hash["name"] = LiquidAny.new(name)
      collection_hash["label"] = LiquidAny.new(name)
      collection_hash["output"] = LiquidAny.new(collection.defaults.output?)

      docs_array = [] of LiquidAny
      collection.resources.each do |resource|
        doc_hash = {} of String => LiquidAny
        doc_hash["url"] = LiquidAny.new(resource.url.try(&.to_s) || "")
        doc_hash["title"] = LiquidAny.new(resource["title"]?.try(&.as_s) || "")
        docs_array << LiquidAny.new(doc_hash)
      end
      collection_hash["docs"] = LiquidAny.new(docs_array)

      collections_array << LiquidAny.new(collection_hash)
    end

    collections_hash = {} of String => LiquidAny
    collections_array.each do |collection_any|
      collection = collection_any.raw.as(Hash(String, LiquidAny))
      collection_name = collection["name"].as_s
      collections_hash[collection_name] = collection_any
    end
    LiquidAny.new(collections_hash)
  end

  private def build_tags_hash : LiquidAny
    tags_hash = Hash(String, Array(LiquidAny)).new
    @site.collections.each do |name, collection|
      collection.resources.each do |resource|
        if tags_value = resource["tags"]?
          resource_hash = {} of String => LiquidAny
          resource_hash["url"] = LiquidAny.new(resource.url.try(&.to_s) || "")
          resource_hash["title"] = LiquidAny.new(resource["title"]?.try(&.as_s) || "")
          resource_hash["date"] = LiquidAny.new(resource.date.to_s)
          resource_hash["slug"] = LiquidAny.new(resource.slug)
          resource_hash["collection"] = LiquidAny.new(name)

          tags_list = if tags_value.is_a?(YAML::Any)
                        if tags_array = tags_value.as_a?
                          tags_array.map(&.as_s)
                        elsif tags_string = tags_value.as_s?
                          tags_string.split(/[,\s]+/).map(&.strip).reject(&.empty?)
                        else
                          [] of String
                        end
                      else
                        [] of String
                      end

          tags_list.each do |tag_name|
            tags_hash[tag_name] ||= [] of LiquidAny
            tags_hash[tag_name] << LiquidAny.new(resource_hash)
          end
        end
      end
    end

    tags_array = [] of LiquidAny
    tags_hash.each do |tag_name, resources|
      tag_pair = [] of LiquidAny
      tag_pair << LiquidAny.new(tag_name)
      tag_pair << LiquidAny.new(resources)
      tags_array << LiquidAny.new(tag_pair)
    end
    LiquidAny.new(tags_array)
  end

  private def build_posts_hash : LiquidAny
    posts_array = [] of LiquidAny
    if posts_collection = @site.collections["posts"]?
      sorted_posts = posts_collection.resources.sort_by(&.date).reverse!

      sorted_posts.each do |post|
        post_hash = {} of String => LiquidAny
        post_hash["url"] = LiquidAny.new(post.url.try(&.to_s) || "")
        post_hash["title"] = LiquidAny.new(post["title"]?.try(&.as_s) || "")
        post_hash["date"] = LiquidAny.new(post.date.to_s)
        post_hash["slug"] = LiquidAny.new(post.slug)
        post_hash["excerpt"] = LiquidAny.new(post["excerpt"]?.try(&.as_s) || "")
        post_hash["content"] = LiquidAny.new(post.content || "")

        post.frontmatter.each do |k, v|
          post_hash[k.to_s] = convert_yaml_to_liquid(v)
        end

        # Include defaults (e.g., read_time: true from _config.yml defaults)
        post.defaults.each do |k, v|
          next if post_hash.has_key?(k.to_s)
          post_hash[k.to_s] = convert_yaml_to_liquid(v)
        end

        posts_array << LiquidAny.new(post_hash)
      end
    end
    LiquidAny.new(posts_array)
  end

  private def build_config_hash : LiquidAny
    config_hash = {} of String => LiquidAny

    config_hash["source"] = LiquidAny.new(@site.config.source)
    config_hash["destination"] = LiquidAny.new(@site.config.destination)
    config_hash["collections_dir"] = LiquidAny.new(@site.config.collections_dir)
    config_hash["layouts_dir"] = LiquidAny.new(@site.config.layouts_dir)
    config_hash["data_dir"] = LiquidAny.new(@site.config.data_dir)
    config_hash["includes_dir"] = LiquidAny.new(@site.config.includes_dir)
    config_hash["port"] = LiquidAny.new(@site.config.port)
    config_hash["host"] = LiquidAny.new(@site.config.host)
    config_hash["baseurl"] = LiquidAny.new(@site.config.baseurl)
    config_hash["paginate_path"] = LiquidAny.new(@site.config.paginate_path)

    @site.config.yaml_unmapped.each do |k, v|
      key = k.to_s
      next if config_hash.has_key?(key)

      case raw = v.raw
      when String
        config_hash[key] = LiquidAny.new(raw)
      when Int32, Int64, Float64, Bool
        config_hash[key] = LiquidAny.new(raw)
      when Nil
      when Hash
        hash = {} of String => LiquidAny
        raw.each do |yaml_key, yaml_value|
          hash_key = yaml_key.is_a?(String) ? yaml_key : yaml_key.to_s
          if yaml_value.is_a?(YAML::Any)
            hash[hash_key] = convert_yaml_to_liquid(yaml_value)
          elsif yaml_value.nil?
            hash[hash_key] = LiquidAny.new("")
          else
            hash[hash_key] = LiquidAny.new(yaml_value.to_s)
          end
        end
        config_hash[key] = LiquidAny.new(hash)
      when Array
        array = raw.map do |item|
          if item.is_a?(YAML::Any)
            convert_yaml_to_liquid(item)
          elsif item.nil?
            LiquidAny.new("")
          else
            LiquidAny.new(item.to_s)
          end
        end
        config_hash[key] = LiquidAny.new(array)
      else
        config_hash[key] = LiquidAny.new(raw.to_s)
      end
    end

    LiquidAny.new(config_hash)
  end

  private def build_data_hash : LiquidAny
    data_hash = {} of String => LiquidAny

    @site.data.each do |key, value|
      data_hash[key] = convert_yaml_to_liquid(value)
    end

    data_hash["ui-text"] ||= LiquidAny.new({} of String => LiquidAny)

    LiquidAny.new(data_hash)
  end

  private def build_page_hash(resource : Resource) : Hash(String, LiquidAny)
    page_hash = {} of String => LiquidAny

    url = resource.url.try(&.to_s) || ""
    path = resource.slug || ""
    page_hash["name"] = LiquidAny.new(resource.name)

    if url.ends_with?("/index.html") || url == "/index.html"
      url = "/"
    end

    page_hash["url"] = LiquidAny.new(url)
    page_hash["path"] = LiquidAny.new(path)
    add_date_to_page_hash(page_hash, resource)

    resource.frontmatter.each do |k, v|
      page_hash[k.to_s] = convert_yaml_to_liquid(v)
    end

    # Include defaults (e.g., read_time: true from _config.yml defaults)
    resource.defaults.each do |k, v|
      next if page_hash.has_key?(k.to_s)
      page_hash[k.to_s] = convert_yaml_to_liquid(v)
    end

    # Include content for read_time calculation
    page_hash["content"] = LiquidAny.new(resource.content || "")

    unless page_hash.has_key?("layout")
      if layout_value = resource["layout"]?
        page_hash["layout"] = LiquidAny.new(layout_value.as_s)
      end
    end

    add_toc_to_page_hash(page_hash, resource)

    page_hash["authors"] ||= LiquidAny.new([] of LiquidAny)
    page_hash["author"] ||= LiquidAny.new("")
    page_hash["excerpt"] ||= LiquidAny.new("")
    page_hash["locale"] ||= LiquidAny.new(@site.config["locale"]?.try(&.as_s) || "en")

    page_hash
  end

  private def build_paginator_hash(resource : Resource) : Hash(String, LiquidAny)
    paginator_hash = {} of String => LiquidAny

    if paginator = resource.paginator
      paginator_hash["page"] = LiquidAny.new(paginator.page)
      paginator_hash["per_page"] = LiquidAny.new(paginator.per_page)
      paginator_hash["total_pages"] = LiquidAny.new(paginator.total_pages)
      paginator_hash["total_items"] = LiquidAny.new(paginator.total_items)
      paginator_hash["previous_page"] = LiquidAny.new(paginator.previous_page)
      paginator_hash["previous_page_path"] = LiquidAny.new(paginator.previous_page_path)
      paginator_hash["next_page"] = LiquidAny.new(paginator.next_page)
      paginator_hash["next_page_path"] = LiquidAny.new(paginator.next_page_path)
      paginator_hash["first_page"] = LiquidAny.new(paginator.first_page)
      paginator_hash["last_page"] = LiquidAny.new(paginator.last_page)
      paginator_hash["first_page_path"] = LiquidAny.new(paginator.first_page_path)
      paginator_hash["last_page_path"] = LiquidAny.new(paginator.last_page_path)

      page_trail_array = paginator.page_trail.map do |trail|
        trail_hash = {} of String => LiquidAny
        trail_hash["num"] = LiquidAny.new(trail.num)
        trail_hash["path"] = LiquidAny.new(trail.path)
        LiquidAny.new(trail_hash)
      end
      paginator_hash["page_trail"] = LiquidAny.new(page_trail_array)

      posts_array = [] of LiquidAny
      paginator.items.each do |item|
        post_hash = {} of String => LiquidAny
        post_hash["url"] = LiquidAny.new(item.url.try(&.to_s) || "")
        post_hash["title"] = LiquidAny.new(item["title"]?.try(&.as_s) || "")

        item.frontmatter.each do |k, v|
          post_hash[k.to_s] = convert_yaml_to_liquid(v)
        end

        posts_array << LiquidAny.new(post_hash)
      end
      paginator_hash["posts"] = LiquidAny.new(posts_array)
    else
      paginator_hash["page"] = LiquidAny.new(1)
      paginator_hash["per_page"] = LiquidAny.new(0)
      paginator_hash["total_pages"] = LiquidAny.new(1)
      paginator_hash["total_items"] = LiquidAny.new(0)
      paginator_hash["previous_page"] = LiquidAny.new(nil)
      paginator_hash["previous_page_path"] = LiquidAny.new("")
      paginator_hash["next_page"] = LiquidAny.new(nil)
      paginator_hash["next_page_path"] = LiquidAny.new("")
      paginator_hash["first_page"] = LiquidAny.new(1)
      paginator_hash["last_page"] = LiquidAny.new(1)
      paginator_hash["first_page_path"] = LiquidAny.new("")
      paginator_hash["last_page_path"] = LiquidAny.new("")
      paginator_hash["page_trail"] = LiquidAny.new([] of LiquidAny)
      paginator_hash["posts"] = LiquidAny.new([] of LiquidAny)
    end

    paginator_hash
  end

  private def add_toc_to_page_hash(page_hash : Hash(String, LiquidAny), resource : Resource) : Nil
    if toc_value = resource["toc"]?
      unless toc_value.is_a?(YAML::Any) && toc_value.as_bool? == false
        if toc_string = toc_value.as_s?
          page_hash["toc"] = LiquidAny.new(toc_string) unless toc_string.empty?
        end
      end
    end
  end

  private def add_date_to_page_hash(page_hash : Hash(String, LiquidAny), resource : Resource) : Nil
    collection_name = resource.collection.try(&.name)
    if collection_name == "posts" || resource.frontmatter.has_key?("date")
      page_hash["date"] = LiquidAny.new(resource.date.to_s)
    end
  end

  private def build_layout_hash(frontmatter : Frontmatter) : Hash(String, LiquidAny)
    layout_hash = {} of String => LiquidAny

    frontmatter.each do |k, v|
      layout_hash[k.to_s] = convert_yaml_to_liquid(v)
    end

    layout_hash
  end

  private def convert_yaml_to_liquid(value : YAML::Any) : LiquidAny
    case raw = value.raw
    when Hash
      hash = {} of String => LiquidAny
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

  private def sanitize_hash(hash : Hash(String, LiquidAny)) : Hash(String, LiquidAny)
    sanitized = {} of String => LiquidAny

    hash.each do |key, value|
      case raw = value.raw
      when Nil
        sanitized[key] = LiquidAny.new("")
      when Hash
        sanitized[key] = LiquidAny.new(sanitize_nested_hash(raw))
      when Array
        sanitized[key] = LiquidAny.new(sanitize_array(raw))
      else
        sanitized[key] = value
      end
    end

    sanitized
  end

  private def sanitize_nested_hash(raw : Hash) : Hash(String, LiquidAny)
    nested = {} of String => LiquidAny
    raw.each do |k, v|
      key_str = k.is_a?(String) ? k : k.to_s
      if v.is_a?(LiquidAny)
        temp_hash = {key_str => v}
        temp_sanitized = sanitize_hash(temp_hash)
        nested[key_str] = temp_sanitized[key_str]
      elsif v.nil?
        nested[key_str] = LiquidAny.new("")
      else
        nested[key_str] = LiquidAny.new(v)
      end
    end
    nested
  end

  private def sanitize_array(raw : Array) : Array(LiquidAny)
    raw.map do |item|
      if item.is_a?(LiquidAny)
        item_raw = item.raw
        if item_raw.nil?
          LiquidAny.new("")
        elsif item_raw.is_a?(Hash)
          temp_hash = {} of String => LiquidAny
          item_raw.each do |k, v|
            key_str = k.is_a?(String) ? k : k.to_s
            temp_hash[key_str] = v.is_a?(LiquidAny) ? v : LiquidAny.new(v || "")
          end
          LiquidAny.new(temp_hash)
        else
          item
        end
      elsif item.nil?
        LiquidAny.new("")
      else
        LiquidAny.new(item)
      end
    end
  end
end
