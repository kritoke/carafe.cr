require "liquid"
require "../processor"
require "./liquid_renderer"

# Liquid preprocessor - renders Liquid templates in any text file
# This must run BEFORE other processors like Sass
class Carafe::Processor::Liquid < Carafe::Processor
  include LiquidRenderer

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

    rendered = render_liquid(source, resource, site)
    output << (rendered.empty? ? source : rendered)

    true
  rescue ex
    STDERR.puts "ERROR rendering Liquid in #{resource.slug}: #{ex.message}"
    output << source
    true
  end
end
