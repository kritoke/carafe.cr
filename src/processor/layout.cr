require "crinja"
require "crinja/liquid"
require "../processor"
require "../crinja_lib"

class Carafe::Processor::Layout < Carafe::Processor
  alias Template = ::Crinja::Template

  transforms "*": "output"

  getter crinja : ::Crinja

  getter layouts_path : String

  getter layouts : Hash(String, {Template, Frontmatter})

  def initialize(@site : Site = Site.new, layouts_path : String? = nil, includes_path : String? = nil)
    @layouts_path = layouts_path || File.join(site.config.source, site.config.layouts_dir)
    includes_path ||= File.join(site.config.source, site.config.includes_dir)

    @layouts = Hash(String, {Template, Frontmatter}).new do |hash, key|
      hash[key] = load_layout(key)
    end

    @crinja = ::Crinja.liquid_support
    @crinja.loader = ::Crinja::Loader::FileSystemLoader.new(File.expand_path(includes_path, site.site_dir))
  end

  def process(resource : Resource, input : IO, output : IO) : Bool
    layout_name = resource["layout"]?.try &.as_s?

    if !layout_name || layout_name == "none"
      return false
    end

    content = input.gets_to_end

    loop do
      layout_template, frontmatter = layouts[layout_name.to_s]

      variables = {
        "content" => ::Crinja::SafeString.new(content),
        "layout"  => to_native(frontmatter).as_h,
        "post"    => to_native(resource.frontmatter).as_h,
        "page"    => to_native(resource.frontmatter).as_h,
        "site"    => {"config" => to_native(@site.config)},
      }

      layout_name = frontmatter["layout"]?.try(&.as_s?)

      content = layout_template.render(variables)

      if !layout_name || layout_name == "none"
        break
      end
    end

    output << content
    output << "\n"
    true
  end

  def load_layout(layout_name : String) : {Template, Frontmatter}
    file_pattern = File.join(File.expand_path(layouts_path, @site.site_dir), "#{layout_name}.*")
    file_path = Dir[file_pattern].first?

    raise "Layout not found: #{layout_name.inspect} (layouts_path: #{layouts_path}) at #{file_pattern}" unless file_path

    File.open(file_path) do |file|
      frontmatter = Frontmatter.read_frontmatter(file) || Frontmatter.new
      content = file.gets_to_end

      template = Template.new(content, crinja, layout_name, file_path)

      return template, frontmatter
    end
  end

  private def to_native(value : Frontmatter) : ::Crinja::Value
    native = {} of String => ::Crinja::Value
    value.each do |k, v|
      native[k] = to_native(v)
    end
    ::Crinja::Value.new(native)
  end

  private def to_native(value : ::YAML::Any) : ::Crinja::Value
    to_native(value.raw)
  end

  private def to_native(value : Hash) : ::Crinja::Value
    native = {} of String => ::Crinja::Value
    value.each do |k, v|
      k_str = k.is_a?(::YAML::Any) ? (k.as_s? || k.to_s) : k.to_s
      native[k_str] = to_native(v)
    end
    ::Crinja::Value.new(native)
  end

  private def to_native(value : Array) : ::Crinja::Value
    native = [] of ::Crinja::Value
    value.each do |v|
      native << to_native(v)
    end
    ::Crinja::Value.new(native)
  end

  private def to_native(value) : ::Crinja::Value
    ::Crinja::Value.new(value)
  end
end
