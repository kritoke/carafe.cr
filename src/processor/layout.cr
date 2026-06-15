require "liquid"
require "../processor"
require "../jekyll_compat"
require "../jekyll_compat/liquid_context_builder"
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

      layout_template = JekyllCompat::Preprocessor.preprocess(layout_template)
      layout_template = process_includes(layout_template, resource)

      liquid_context = Carafe::LiquidContextBuilder.build(@site, resource, content.strip)

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
end
