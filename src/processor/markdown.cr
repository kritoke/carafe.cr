require "markd"
require "../processor"
require "../plugins/carafe_toc"

class Carafe::Processor::Markdown < Carafe::Processor
  transforms "markdown": "html"

  file_extensions "markdown": {".md", ".markdown"}

  getter options = Markd::Options.new(toc: true)

  def initialize(site = nil)
  end

  def process(resource : Resource, input : IO, output : IO) : Bool
    rendered = Markd.to_html(input.gets_to_end, options)

    # Generate TOC and auto-inject into content
    toc_enabled = resource["toc"]?
    if toc_enabled.nil? || toc_enabled.as_s? == "true" || (toc_enabled.raw == true)
      toc_html = Carafe::Plugins::CarafeToc.generate_toc(rendered)
      unless toc_html.empty?
        # Store TOC in frontmatter for layouts that want to use it
        resource.frontmatter["toc"] = toc_html

        # Auto-inject TOC into content for theme compatibility
        # Insert TOC at the beginning of the content (after any layout elements)
        # This works with Minimal Mistakes and other themes
        rendered = toc_html + "\n" + rendered
      end
    end

    output << rendered
    true
  end
end
