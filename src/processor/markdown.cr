require "markd"
require "../processor"
require "../plugins/content/toc"

class Carafe::Processor::Markdown < Carafe::Processor
  transforms "markdown": "html"

  file_extensions "markdown": {".md", ".markdown"}

  getter options = Markd::Options.new(toc: true)

  def initialize(site = nil)
  end

  def process(resource : Resource, input : IO, output : IO) : Bool
    rendered = Markd.to_html(input.gets_to_end, options)

    toc_enabled = resource["toc"]?
    if toc_enabled.nil? || toc_enabled.as_s? == "true" || (toc_enabled.raw == true)
      toc_html = Carafe::Plugins::Toc.generate_toc(rendered)
      unless toc_html.empty?
        resource.frontmatter["toc"] = toc_html

        rendered = toc_html + "\n" + rendered
      end
    end

    output << rendered
    true
  end
end
