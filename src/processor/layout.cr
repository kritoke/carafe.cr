require "liquid"
require "../processor"
require "../jekyll_compat"
require "../plugins/content/dark_mode"

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
        template = Liquid::Template.parse(layout_template)
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
    file_pattern = File.join(File.expand_path(layouts_path, @site.site_dir), "#{layout_name}.*")
    file_path = Dir[file_pattern].first?

    raise "Layout not found: #{layout_name.inspect} (layouts_path: #{layouts_path}) at #{file_pattern}" unless file_path

    File.open(file_path) do |file|
      frontmatter = Frontmatter.read_frontmatter(file) || Frontmatter.new
      content = file.gets_to_end

      return content, frontmatter
    end
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

  private def build_liquid_context(resource : Resource, content : String, frontmatter : Frontmatter) : Liquid::Context
    liquid_context = Liquid::Context.new
    liquid_context.set("template_path", Liquid::Any.new(@site.site_dir))

    site_hash = build_site_hash
    liquid_context.set("site", sanitize_hash(site_hash))

    if site_url = @site.config["url"]?.try(&.as_s)
      JekyllCompat::LiquidFilters.site_url = site_url
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

  private def build_site_hash : Hash(String, Liquid::Any)
    site_hash = build_basic_site_config
    site_hash["collections"] = build_collections_hash
    site_hash["tags"] = build_tags_hash
    site_hash["posts"] = build_posts_hash
    add_optional_fields(site_hash)
    site_hash
  end

  private def build_basic_site_config : Hash(String, Liquid::Any)
    site_hash = {} of String => Liquid::Any
    site_hash["config"] = build_config_hash
    site_hash["data"] = build_data_hash
    site_hash["locale"] = Liquid::Any.new(@site.config["locale"]?.try(&.as_s) || "en")
    site_hash["title"] = Liquid::Any.new(@site.config["title"]?.try(&.as_s) || "Site")
    site_hash["name"] = Liquid::Any.new(@site.config["name"]?.try(&.as_s) || @site.config["title"]?.try(&.as_s) || "Site")
    site_hash["title_separator"] = Liquid::Any.new(@site.config["title_separator"]?.try(&.as_s) || "|")
    site_hash["baseurl"] = Liquid::Any.new(@site.config["baseurl"]?.try(&.as_s) || "")
    site_hash["url"] = Liquid::Any.new(@site.config["url"]?.try(&.as_s) || "")
    site_hash["time"] = Liquid::Any.new(Time.local.to_s)
    site_hash
  end

  private def add_optional_fields(site_hash : Hash(String, Liquid::Any)) : Nil
    site_hash["subtitle"] = Liquid::Any.new(@site.config["subtitle"]?.try(&.as_s) || "")

    if footer_value = @site.config["footer"]?
      site_hash["footer"] = convert_yaml_to_liquid(footer_value)
    end

    if author_value = @site.config["author"]?
      site_hash["author"] = convert_yaml_to_liquid(author_value)
    end

    site_hash["email"] = Liquid::Any.new(@site.config["email"]?.try(&.as_s) || "")

    site_hash["search"] = Liquid::Any.new(@site.config["search"]?.try(&.as_bool?) || false)
    if search_provider = @site.config["search_provider"]?.try(&.as_s)
      site_hash["search_provider"] = Liquid::Any.new(search_provider)
    end
  end

  private def build_collections_hash : Liquid::Any
    collections_array = [] of Liquid::Any
    @site.collections.each do |name, collection|
      collection_hash = {} of String => Liquid::Any
      collection_hash["name"] = Liquid::Any.new(name)
      collection_hash["label"] = Liquid::Any.new(name)
      collection_hash["output"] = Liquid::Any.new(collection.defaults.output?)

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

    collections_hash = {} of String => Liquid::Any
    collections_array.each do |collection_any|
      collection = collection_any.raw.as(Hash(String, Liquid::Any))
      collection_name = collection["name"].as_s
      collections_hash[collection_name] = collection_any
    end
    Liquid::Any.new(collections_hash)
  end

  private def build_tags_hash : Liquid::Any
    tags_hash = Hash(String, Array(Liquid::Any)).new
    @site.collections.each do |name, collection|
      collection.resources.each do |resource|
        if tags_value = resource["tags"]?
          resource_hash = {} of String => Liquid::Any
          resource_hash["url"] = Liquid::Any.new(resource.url.try(&.to_s) || "")
          resource_hash["title"] = Liquid::Any.new(resource["title"]?.try(&.as_s) || "")
          resource_hash["date"] = Liquid::Any.new(resource.date.to_s)
          resource_hash["slug"] = Liquid::Any.new(resource.slug)
          resource_hash["collection"] = Liquid::Any.new(name)

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
            tags_hash[tag_name] ||= [] of Liquid::Any
            tags_hash[tag_name] << Liquid::Any.new(resource_hash)
          end
        end
      end
    end

    tags_array = [] of Liquid::Any
    tags_hash.each do |tag_name, resources|
      tag_pair = [] of Liquid::Any
      tag_pair << Liquid::Any.new(tag_name)
      tag_pair << Liquid::Any.new(resources)
      tags_array << Liquid::Any.new(tag_pair)
    end
    Liquid::Any.new(tags_array)
  end

  private def build_posts_hash : Liquid::Any
    posts_array = [] of Liquid::Any
    if posts_collection = @site.collections["posts"]?
      sorted_posts = posts_collection.resources.sort_by(&.date).reverse!

      sorted_posts.each do |post|
        post_hash = {} of String => Liquid::Any
        post_hash["url"] = Liquid::Any.new(post.url.try(&.to_s) || "")
        post_hash["title"] = Liquid::Any.new(post["title"]?.try(&.as_s) || "")
        post_hash["date"] = Liquid::Any.new(post.date.to_s)
        post_hash["slug"] = Liquid::Any.new(post.slug)
        post_hash["excerpt"] = Liquid::Any.new(post["excerpt"]?.try(&.as_s) || "")
        post_hash["content"] = Liquid::Any.new(post.content || "")

        post.frontmatter.each do |k, v|
          post_hash[k.to_s] = convert_yaml_to_liquid(v)
        end

        posts_array << Liquid::Any.new(post_hash)
      end
    end
    Liquid::Any.new(posts_array)
  end

  private def build_config_hash : Liquid::Any
    config_hash = {} of String => Liquid::Any

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

    @site.config.yaml_unmapped.each do |k, v|
      key = k.to_s
      next if config_hash.has_key?(key)

      case raw = v.raw
      when String
        config_hash[key] = Liquid::Any.new(raw)
      when Int32, Int64, Float64, Bool
        config_hash[key] = Liquid::Any.new(raw)
      when Nil
      when Hash
        hash = {} of String => Liquid::Any
        raw.each do |yaml_key, yaml_value|
          hash_key = yaml_key.is_a?(String) ? yaml_key : yaml_key.to_s
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

    data_hash["ui-text"] ||= Liquid::Any.new({} of String => Liquid::Any)

    Liquid::Any.new(data_hash)
  end

  private def build_page_hash(resource : Resource) : Hash(String, Liquid::Any)
    page_hash = {} of String => Liquid::Any

    url = resource.url.try(&.to_s) || ""
    path = resource.slug || ""
    page_hash["name"] = Liquid::Any.new(resource.name)

    if url.ends_with?("/index.html") || url == "/index.html"
      url = "/"
    end

    page_hash["url"] = Liquid::Any.new(url)
    page_hash["path"] = Liquid::Any.new(path)
    add_date_to_page_hash(page_hash, resource)

    resource.frontmatter.each do |k, v|
      page_hash[k.to_s] = convert_yaml_to_liquid(v)
    end

    unless page_hash.has_key?("layout")
      if layout_value = resource["layout"]?
        page_hash["layout"] = Liquid::Any.new(layout_value.as_s)
      end
    end

    add_toc_to_page_hash(page_hash, resource)

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

      posts_array = [] of Liquid::Any
      paginator.items.each do |item|
        post_hash = {} of String => Liquid::Any
        post_hash["url"] = Liquid::Any.new(item.url.try(&.to_s) || "")
        post_hash["title"] = Liquid::Any.new(item["title"]?.try(&.as_s) || "")

        item.frontmatter.each do |k, v|
          post_hash[k.to_s] = convert_yaml_to_liquid(v)
        end

        posts_array << Liquid::Any.new(post_hash)
      end
      paginator_hash["posts"] = Liquid::Any.new(posts_array)
    else
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

  private def add_toc_to_page_hash(page_hash : Hash(String, Liquid::Any), resource : Resource) : Nil
    if toc_value = resource["toc"]?
      unless toc_value.is_a?(YAML::Any) && toc_value.as_bool? == false
        if toc_string = toc_value.as_s?
          page_hash["toc"] = Liquid::Any.new(toc_string) unless toc_string.empty?
        end
      end
    end
  end

  private def add_date_to_page_hash(page_hash : Hash(String, Liquid::Any), resource : Resource) : Nil
    collection_name = resource.collection.try(&.name)
    if collection_name == "posts" || resource.frontmatter.has_key?("date")
      page_hash["date"] = Liquid::Any.new(resource.date.to_s)
    end
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
      Liquid::Any.new("")
    else
      Liquid::Any.new(raw.to_s)
    end
  end

  private def sanitize_hash(hash : Hash(String, Liquid::Any)) : Hash(String, Liquid::Any)
    sanitized = {} of String => Liquid::Any

    hash.each do |key, value|
      case raw = value.raw
      when Nil
        sanitized[key] = Liquid::Any.new("")
      when Hash
        sanitized[key] = Liquid::Any.new(sanitize_nested_hash(raw))
      when Array
        sanitized[key] = Liquid::Any.new(sanitize_array(raw))
      else
        sanitized[key] = value
      end
    end

    sanitized
  end

  private def sanitize_nested_hash(raw : Hash) : Hash(String, Liquid::Any)
    nested = {} of String => Liquid::Any
    raw.each do |k, v|
      key_str = k.is_a?(String) ? k : k.to_s
      if v.is_a?(Liquid::Any)
        temp_hash = {key_str => v}
        temp_sanitized = sanitize_hash(temp_hash)
        nested[key_str] = temp_sanitized[key_str]
      elsif v.nil?
        nested[key_str] = Liquid::Any.new("")
      else
        nested[key_str] = Liquid::Any.new(v)
      end
    end
    nested
  end

  private def sanitize_array(raw : Array) : Array(Liquid::Any)
    raw.map do |item|
      if item.is_a?(Liquid::Any)
        item_raw = item.raw
        if item_raw.nil?
          Liquid::Any.new("")
        elsif item_raw.is_a?(Hash)
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
  end
end
