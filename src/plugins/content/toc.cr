require "../plugin"
require "liquid"
require "xml"

module Carafe::Plugins::Toc
  struct Entry
    property level : Int32
    property id : String
    property text : String
    property children : Array(Entry)

    def initialize(@level : Int32, @id : String, @text : String)
      @children = [] of Entry
    end
  end

  class Generator
    property min_level : Int32 = 1
    property max_level : Int32 = 6

    def initialize(@min_level = 1, @max_level = 6)
    end

    def generate(html_content : String) : String
      entries = parse_headings(html_content)
      return "" if entries.empty?

      build_full_toc_html(entries)
    end

    private def parse_headings(html_content : String) : Array(Entry)
      entries = [] of Entry
      stack = [] of Tuple(Int32, Entry)

      html_content.scan(/<h([1-6])[^>]*>\s*<a id=["']anchor-([^"']+)["'][^>]*>.*?<\/a>\s*(.*?)<\/h\1>/m) do |match|
        level = match[1].to_i
        id = "anchor-#{match[2]}"
        text = strip_html_tags(match[3])

        next if level < min_level || level > max_level

        if match[0].includes?("class=") && match[0].includes?("no_toc")
          next
        end

        entry = Entry.new(level, id, text)

        while !stack.empty? && stack.last[0] >= level
          stack.pop
        end

        if stack.empty?
          entries << entry
        else
          parent = stack.last[1]
          parent.children << entry
        end

        stack.push({level, entry})
      end

      entries
    end

    private def build_full_toc_html(entries : Array(Entry)) : String
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

    private def build_toc_html(entries : Array(Entry), indent : String = "") : String
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

    private def strip_html_tags(html : String) : String
      html.gsub(/<[^>]*>/, "").strip
    end
  end

  class TocFilter
    extend Liquid::Filters::Filter

    def self.filter(data : Liquid::Any, args : Array(Liquid::Any), options : Hash(String, Liquid::Any)) : Liquid::Any
      return Liquid::Any.new("") if data.raw.nil?

      html_content = data.as_s
      generator = Generator.new

      toc_html = generator.generate(html_content)
      Liquid::Any.new(toc_html)
    end
  end

  def self.generate_toc(html_content : String) : String
    generator = Generator.new
    generator.generate(html_content)
  end
end

class Carafe::Plugins::TocPlugin < Carafe::Plugin
  def name : String
    "toc"
  end

  def version : String
    "0.1.0"
  end

  def enabled?(config : Carafe::Config) : Bool
    toc_enabled = config["toc"]?
    return true if toc_enabled.nil?

    toc_enabled.as_bool? || (toc_enabled.as_s? == "true")
  end

  def register(site : Carafe::Site) : Nil
    puts "TocPlugin: Registering TOC filter" unless site.config.quiet?
    Liquid::Filters::FilterRegister.register "toc", Carafe::Plugins::Toc::TocFilter
  end
end

Carafe::Plugin.register_implementation(Carafe::Plugins::TocPlugin)
