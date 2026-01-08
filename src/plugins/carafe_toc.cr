require "../carafe"
require "../plugin"
require "liquid"
require "xml"

module Carafe::Plugins::CarafeToc
  # Table of Contents entry
  struct TocEntry
    property level : Int32
    property id : String
    property text : String
    property children : Array(TocEntry)

    def initialize(@level : Int32, @id : String, @text : String)
      @children = [] of TocEntry
    end
  end

  # TOC Generator - parses HTML and generates nested TOC structure
  class TocGenerator
    property min_level : Int32 = 1
    property max_level : Int32 = 6

    def initialize(@min_level = 1, @max_level = 6)
    end

    # Generate TOC HTML from content
    def generate(html_content : String) : String
      entries = parse_headings(html_content)
      return "" if entries.empty?

      build_full_toc_html(entries)
    end

    # Parse HTML to extract heading structure
    private def parse_headings(html_content : String) : Array(TocEntry)
      entries = [] of TocEntry
      stack = [] of Tuple(Int32, TocEntry)

      # Parse HTML and extract headings
      # Markd with toc option adds: <h2><a id="anchor-TITLE" class="anchor" href="#anchor-TITLE"></a>Heading Text</h2>
      # We need to extract the heading level, anchor id, and heading text
      html_content.scan(/<h([1-6])[^>]*>\s*<a id=["']anchor-([^"']+)["'][^>]*>.*?<\/a>\s*(.*?)<\/h\1>/m) do |match|
        level = match[1].to_i
        id = "anchor-#{match[2]}"
        text = strip_html_tags(match[3])

        # Skip if outside configured levels
        next if level < min_level || level > max_level

        # Skip if heading has no_toc class
        if match[0].includes?("class=") && match[0].includes?("no_toc")
          next
        end

        entry = TocEntry.new(level, id, text)

        # Pop entries from stack that are >= current level
        while !stack.empty? && stack.last[0] >= level
          stack.pop
        end

        # Add to parent or root
        if stack.empty?
          entries << entry
        else
          parent = stack.last[1]
          parent.children << entry
        end

        # Push current entry to stack
        stack.push({level, entry})
      end

      entries
    end

    # Build full TOC HTML with wrapper elements
    private def build_full_toc_html(entries : Array(TocEntry)) : String
      return "" if entries.empty?

      inner_html = build_toc_html(entries, "      ")
      return "" if inner_html.empty?

      <<-HTML
      <aside class="sidebar__right">
        <nav class="toc">
          <header><h4 class="nav__title"><i class="fas fa-file-alt"></i> On this page</h4></header>
          #{inner_html}
        </nav>
      </aside>
      HTML
    end

    # Build nested HTML list from entries
    private def build_toc_html(entries : Array(TocEntry), indent : String = "") : String
      return "" if entries.empty?

      html = "#{indent}<ul class=\"toc__menu\">\n"
      entries.each do |entry|
        html += "#{indent}  <li>\n"
        html += "#{indent}    <a href=\"##{entry.id}\">#{entry.text}</a>\n"

        unless entry.children.empty?
          html += build_toc_html(entry.children, "#{indent}    ")
        end

        html += "#{indent}  </li>\n"
      end
      html += "#{indent}</ul>\n"

      html
    end

    # Strip HTML tags from text
    private def strip_html_tags(html : String) : String
      html.gsub(/<[^>]*>/, "").strip
    end
  end

  # Liquid filter for TOC generation
  class TocFilter
    extend Liquid::Filters::Filter

    def self.filter(data : Liquid::Any, args : Array(Liquid::Any), options : Hash(String, Liquid::Any)) : Liquid::Any
      return Liquid::Any.new("") if data.raw.nil?

      html_content = data.as_s
      generator = TocGenerator.new

      # Parse optional arguments
      args.each do |arg|
        case arg.as_s
        when "min_level"
          # TODO: Parse min_level from args
        when "max_level"
          # TODO: Parse max_level from args
        end
      end

      toc_html = generator.generate(html_content)
      Liquid::Any.new(toc_html)
    end
  end

  # Module method to generate TOC from HTML content
  # This is called from the layout processor when building page data
  def self.generate_toc(html_content : String) : String
    generator = TocGenerator.new
    generator.generate(html_content)
  end
end

# Plugin class
class Carafe::Plugins::CarafeToc::Plugin < Carafe::Plugin
  def name : String
    "carafe_toc"
  end

  def version : String
    "0.1.0"
  end

  def enabled?(config : Carafe::Config) : Bool
    # Check if toc is enabled in config
    toc_enabled = config["toc"]?
    return true if toc_enabled.nil? # Default to enabled if not specified

    toc_enabled.as_bool? || (toc_enabled.as_s? == "true")
  end

  def register(site : Carafe::Site) : Nil
    # Register the TOC filter with Liquid
    puts "CarafeToc: Registering TOC filter" unless site.config.quiet?
    Liquid::Filters::FilterRegister.register "toc", Carafe::Plugins::CarafeToc::TocFilter
  end
end

# Register this plugin
Carafe::Plugin.register_implementation(Carafe::Plugins::CarafeToc::Plugin)
