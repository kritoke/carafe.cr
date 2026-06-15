require "../processor"
require "./liquid_filters"

# Pure builder for the canonical Liquid context.
#
# This module is the single source of truth for the shape of the `site`,
# `page`, `paginator`, `layout`, and `doc` objects exposed to Liquid templates.
# Both `Processor::Liquid` and `Processor::Layout` will consume it (Phase 3/4).
#
# Design constraints (see OpenSpec: unify-liquid-context-builder):
#   - Pure transformation: no STDERR, no file IO, no mutation of inputs.
#   - The only side effect is setting `JekyllCompat::LiquidFilters` class
#     variables (site_url, baseurl), imposed by the liquid shard's class-level
#     filter API.
#   - One `build_doc` implementation used by site.posts, site.tags,
#     collections.docs, and paginator.posts.
#   - One `convert_yaml_to_liquid` implementation.
module Carafe::LiquidContextBuilder
  # Build a fully-populated Liquid::Context for rendering `resource`.
  # `content` is the already-rendered body (nil acceptable for non-layout paths).
  def self.build(site : Site, resource : Resource, content : String? = nil) : LiquidContext
    ctx = LiquidContext.new
    ctx.set("template_path", LiquidAny.new(site.site_dir))
    ctx.set("site", LiquidAny.new(build_site(site)))
    ctx.set("page", LiquidAny.new(build_page(site, resource)))
    ctx.set("paginator", LiquidAny.new(build_paginator(resource)))
    ctx.set("layout", LiquidAny.new(build_layout(resource)))
    ctx.set("content", LiquidAny.new(content || ""))
    ctx.set("post", LiquidAny.new(build_page(site, resource)))
    set_filter_options(ctx, site)
    ctx
  end

  # --- Public per-structure builders (for direct spec assertion) ---

  def self.build_site(site : Site) : Hash(String, LiquidAny)
    site_hash = {} of String => LiquidAny

    site_hash["config"] = LiquidAny.new(build_config(site))
    site_hash["data"] = LiquidAny.new(build_data(site))

    # Scalar metadata — default to "" (never nil/blank)
    site_hash["title"] = LiquidAny.new(site.config["title"]?.try(&.as_s) || "")
    site_hash["name"] = LiquidAny.new(site.config["name"]?.try(&.as_s) || site.config["title"]?.try(&.as_s) || "")
    site_hash["description"] = LiquidAny.new(site.config["description"]?.try(&.as_s) || "")
    site_hash["url"] = LiquidAny.new(site.config["url"]?.try(&.as_s) || "")
    site_hash["baseurl"] = LiquidAny.new(site.config["baseurl"]?.try(&.as_s) || "")
    site_hash["locale"] = LiquidAny.new(site.config["locale"]?.try(&.as_s) || "en")
    site_hash["title_separator"] = LiquidAny.new(site.config["title_separator"]?.try(&.as_s) || "|")
    site_hash["time"] = LiquidAny.new(Time.local.to_s)

    # Collections — HASH keyed by label (canonical shape)
    site_hash["collections"] = build_collections(site)

    # Per-collection convenience aliases (e.g. site.posts, site.tutorials)
    site.collections.each do |name, collection|
      docs = collection.resources.map { |r| LiquidAny.new(build_doc(r, name)) }
      site_hash[name] = LiquidAny.new(docs)
    end

    # site.posts — always present, sorted newest-first
    if posts_collection = site.collections["posts"]?
      sorted = posts_collection.resources.sort
      site_hash["posts"] = LiquidAny.new(sorted.map { |r| LiquidAny.new(build_doc(r, "posts")) })
    else
      site_hash["posts"] = LiquidAny.new([] of LiquidAny)
    end

    # site.tags — hash keyed by tag name → array of docs
    site_hash["tags"] = build_tags(site)

    site_hash
  end

  def self.build_page(site : Site, resource : Resource) : Hash(String, LiquidAny)
    page_hash = {} of String => LiquidAny

    url = resource.url.try(&.to_s) || ""
    page_hash["name"] = LiquidAny.new(resource.name)

    if url.ends_with?("/index.html") || url == "/index.html"
      url = "/"
    end
    page_hash["url"] = LiquidAny.new(url)
    page_hash["path"] = LiquidAny.new(resource.slug || "")

    # Date — present for posts or when frontmatter has "date"
    collection_name = resource.collection.try(&.name)
    if collection_name == "posts" || resource.frontmatter.has_key?("date")
      page_hash["date"] = LiquidAny.new(resource.date.to_s)
    end

    # Frontmatter
    resource.frontmatter.each do |k, v|
      page_hash[k.to_s] = convert_yaml_to_liquid(v)
    end

    # Defaults (e.g., read_time: true from _config.yml)
    resource.defaults.each do |k, v|
      next if page_hash.has_key?(k.to_s)
      page_hash[k.to_s] = convert_yaml_to_liquid(v)
    end

    page_hash["content"] = LiquidAny.new(resource.content || "")

    unless page_hash.has_key?("layout")
      if layout_value = resource["layout"]?
        page_hash["layout"] = LiquidAny.new(layout_value.as_s)
      end
    end

    page_hash["authors"] ||= LiquidAny.new([] of LiquidAny)
    page_hash["author"] ||= LiquidAny.new("")
    page_hash["excerpt"] ||= LiquidAny.new("")
    page_hash["locale"] ||= LiquidAny.new(site.config["locale"]?.try(&.as_s) || "en")

    page_hash
  end

  def self.build_paginator(resource : Resource) : Hash(String, LiquidAny)
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

      posts_array = paginator.items.map { |item| LiquidAny.new(build_doc(item)) }
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

  # Layout frontmatter as liquid values.
  # NOTE: In Phase 3, the Layout processor may pass the layout file's
  # frontmatter separately. For now this uses the resource's frontmatter
  # as a reasonable default for isolated testing.
  def self.build_layout(resource : Resource) : Hash(String, LiquidAny)
    layout_hash = {} of String => LiquidAny
    resource.frontmatter.each do |k, v|
      layout_hash[k.to_s] = convert_yaml_to_liquid(v)
    end
    layout_hash
  end

  # --- Shared doc builder (single implementation for all contexts) ---

  def self.build_doc(resource : Resource, collection_name : String? = nil) : Hash(String, LiquidAny)
    doc = {} of String => LiquidAny

    doc["url"] = LiquidAny.new(resource.url.try(&.to_s) || "")
    doc["title"] = LiquidAny.new(resource["title"]?.try(&.as_s) || resource.slug)
    doc["date"] = LiquidAny.new(resource.date.to_s)
    doc["slug"] = LiquidAny.new(resource.slug)
    doc["path"] = LiquidAny.new(resource.slug || "")
    doc["name"] = LiquidAny.new(resource.name)
    doc["excerpt"] = LiquidAny.new(resource["excerpt"]?.try(&.as_s) || "")
    doc["content"] = LiquidAny.new(resource.content || "")
    doc["tags"] = LiquidAny.new(normalize_string_array(resource["tags"]?))
    doc["categories"] = LiquidAny.new(normalize_string_array(resource["categories"]?))

    if cn = collection_name
      doc["collection"] = LiquidAny.new(cn)
    end

    # Frontmatter (skip keys already set above)
    resource.frontmatter.each do |k, v|
      next if doc.has_key?(k.to_s)
      doc[k.to_s] = convert_yaml_to_liquid(v)
    end

    # Defaults
    resource.defaults.each do |k, v|
      next if doc.has_key?(k.to_s)
      doc[k.to_s] = convert_yaml_to_liquid(v)
    end

    doc
  end

  # --- Private builders ---

  private def self.build_collections(site : Site) : LiquidAny
    collections_hash = {} of String => LiquidAny

    site.collections.each do |name, collection|
      ch = {} of String => LiquidAny
      ch["label"] = LiquidAny.new(name)
      ch["name"] = LiquidAny.new(name)
      ch["output"] = LiquidAny.new(collection.defaults.output?)
      ch["docs"] = LiquidAny.new(collection.resources.map { |r| LiquidAny.new(build_doc(r, name)) })
      collections_hash[name] = LiquidAny.new(ch)
    end

    LiquidAny.new(collections_hash)
  end

  private def self.build_tags(site : Site) : LiquidAny
    temp_tags = Hash(String, Array(LiquidAny)).new

    site.collections.each do |name, collection|
      collection.resources.each do |resource|
        normalize_string_array(resource["tags"]?).each do |tag_any|
          tag_name = tag_any.to_s
          temp_tags[tag_name] ||= [] of LiquidAny
          temp_tags[tag_name] << LiquidAny.new(build_doc(resource, name))
        end
      end
    end

    tags_hash = {} of String => LiquidAny
    temp_tags.each { |tag, docs| tags_hash[tag] = LiquidAny.new(docs) }
    LiquidAny.new(tags_hash)
  end

  private def self.build_config(site : Site) : Hash(String, LiquidAny)
    config_hash = {} of String => LiquidAny

    config_hash["source"] = LiquidAny.new(site.config.source)
    config_hash["destination"] = LiquidAny.new(site.config.destination)
    config_hash["collections_dir"] = LiquidAny.new(site.config.collections_dir)
    config_hash["layouts_dir"] = LiquidAny.new(site.config.layouts_dir)
    config_hash["data_dir"] = LiquidAny.new(site.config.data_dir)
    config_hash["includes_dir"] = LiquidAny.new(site.config.includes_dir)
    config_hash["port"] = LiquidAny.new(site.config.port)
    config_hash["host"] = LiquidAny.new(site.config.host)
    config_hash["baseurl"] = LiquidAny.new(site.config.baseurl)
    config_hash["paginate_path"] = LiquidAny.new(site.config.paginate_path)

    # Unmapped config values (e.g., minimal_mistakes_skin)
    site.config.yaml_unmapped.each do |k, v|
      key = k.to_s
      next if config_hash.has_key?(key)
      config_hash[key] = convert_yaml_to_liquid(v)
    end

    config_hash
  end

  private def self.build_data(site : Site) : Hash(String, LiquidAny)
    data_hash = {} of String => LiquidAny

    site.data.each do |key, value|
      data_hash[key] = convert_yaml_to_liquid(value)
    end

    data_hash["ui-text"] ||= LiquidAny.new({} of String => LiquidAny)

    data_hash
  end

  # --- Shared converters ---

  private def self.convert_yaml_to_liquid(value : YAML::Any) : LiquidAny
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

  # Normalize tags/categories frontmatter value to always be an array.
  # Scalar strings are split on whitespace and commas (Jekyll behavior).
  private def self.normalize_string_array(value : YAML::Any?) : Array(LiquidAny)
    return [] of LiquidAny unless value

    case raw = value.raw
    when String
      raw.split(/[,\s]+/).reject(&.empty?).map { |t| LiquidAny.new(t) }
    when Array
      raw.map { |t| LiquidAny.new(t.to_s) }
    else
      [] of LiquidAny
    end
  end

  # Set global filter config (side effect imposed by liquid shard's
  # class-level filter API) and context-level filter_options.
  private def self.set_filter_options(ctx : LiquidContext, site : Site) : Nil
    site_url = site.config["url"]?.try(&.as_s)
    JekyllCompat::LiquidFilters.site_url = site_url if site_url

    baseurl = site.config.baseurl
    JekyllCompat::LiquidFilters.baseurl = baseurl if baseurl

    ctx.filter_options["url"] = LiquidAny.new(site_url || "")
    ctx.filter_options["baseurl"] = LiquidAny.new(baseurl || "")
  end
end
