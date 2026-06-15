require "liquid"
require "../processor"
require "../jekyll_compat/liquid_context_builder"

# Liquid preprocessor - renders Liquid templates in any text file
# This must run BEFORE other processors like Sass
class Carafe::Processor::Liquid < Carafe::Processor
  transforms "*": "liquid"

  property site : Site?

  getter priority : Priority = Priority::HIGH

  def initialize(@site : Site)
  end

  def process(resource : Resource, input : IO, output : IO) : Bool
    source = input.gets_to_end

    # Skip if empty or no Liquid tags
    # Note: front matter is already stripped by the resource loader
    if source.strip.empty? || !has_liquid_tags?(source)
      output << source
      return true
    end

    unless site = @site
      output << source
      return true
    end

    context = Carafe::LiquidContextBuilder.build(site, resource)
    rendered = LiquidTemplate.parse(source).render(context)
    output << (rendered.empty? ? source : rendered)

    true
  rescue ex
    STDERR.puts "ERROR rendering Liquid in #{resource.slug}: #{ex.message}"
    output << source
    true
  end

  private def has_liquid_tags?(content : String) : Bool
    content.includes?("{{") || content.includes?("{%")
  end
end
