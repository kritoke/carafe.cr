require "liquid"
require "tartrazine"
require "../util/security"

module Liquid::Block
  class JekyllInclude < Include
    JEKYLL_INCLUDE = /^(?<template_name>[\w\-\.\/]+)(?<params>.*)$/

    def initialize(content : String)
      content = content.strip

      if match = content.match JEKYLL_INCLUDE
        @template_vars = {} of String => Expression
        @template_name = match["template_name"]

        params_str = match["params"]? || ""
        if !params_str.strip.empty?
          jekyll_params = /\s*(?<varname>[A-Za-z_]\w*)=(?<value>[^\s]+)/

          params_str.scan(jekyll_params) do |param_match|
            varname = param_match["varname"]
            value = param_match["value"]
            @template_vars[varname] = Expression.new(value)
          end
        end
      else
        @template_vars = {} of String => Expression

        if match = content.match(/^(?<template_name>["'][^"']+["'])(\s+with\s+(?<value>(?:(?:"(?:[^"]|\\")*")|(?:'(?:[^']|\\')*')|(?:[-+]?[0-9]+)|(?:[-!]*(?:[A-Za-z_]\w*)(?:(?:\.[A-Za-z_]\w*)|(?:\[(?:(?:(?:"(?:[^"]|\\")*")|(?:'(?:[^']|\\')*'))|(?:[-+]?[0-9]+)|(?1))\]))*\??))))?/)
          @template_name = match["template_name"].delete("\"").delete("'")
          @template_name += ".liquid" if File.extname(@template_name).empty?

          if match["value"]?
            varname = File.basename(@template_name, File.extname(@template_name))
            @template_vars[varname] = Expression.new(match["value"])
          end
        else
          raise SyntaxError.new("Invalid include Node: #{content}")
        end
      end
    end
  end

  class Highlight < BeginBlock
    getter language : String
    getter? linenos : Bool

    def initialize(content : String)
      parts = content.strip.split
      @language = parts.first? || "text"
      @linenos = parts.includes?("linenos") || parts.includes?("lineos")
    end
  end
end

module Liquid
  class RenderVisitor < Visitor
    private def get_base_path : String
      if template_path_val = @data["template_path"]?
        case raw = template_path_val.raw
        when String
          raw
        else
          "."
        end
      else
        @template_path || "."
      end
    end

    private def get_includes_dir(base_path : String) : String
      if base_path.ends_with?("/_layouts") || base_path.ends_with?("/_layouts/")
        File.join(File.dirname(base_path), "_includes")
      elsif base_path == "."
        "_includes"
      else
        File.join(base_path, "_includes")
      end
    end

    private def process_template_content(template_content : String, include_hash : Hash(String, Liquid::Any)) : String
      if template_content.includes?("assign entries = include.entries")
        if include_hash.has_key?("entries")
          entries_value = include_hash["entries"]?

          if entries_value.is_a?(String)
            entries_str = entries_value.as_s

            if entries_str == "posts" || entries_str == "site.posts"
              template_content = template_content.gsub(/{%-?\s*assign entries = include\.entries.*?%-?%}/, "")
              template_content = template_content.gsub(/{%\s*assign entries = include\.entries.*?%}/, "")
              template_content = template_content.gsub(/{%-?\s*for\s+post\s+in\s+entries\s*-?%}/, "{% for post in site.posts %}")
              template_content = template_content.gsub(/{%\s*for\s+post\s+in\s+entries\s*%}/, "{% for post in site.posts %}")
            else
              template_content = template_content.gsub(/{%-?\s*assign entries = include\.entries.*?%-?%}/, "")
              template_content = template_content.gsub(/{%\s*assign entries = include\.entries.*?%}/, "")
              template_content = template_content.gsub(/{%-?\s*for\s+post\s+in\s+entries\s*-?%}/, "{% for post in site.posts %}")
              template_content = template_content.gsub(/{%\s*for\s+post\s+in\s+entries\s*%}/, "{% for post in site.posts %}")
            end
          else
            template_content = template_content.gsub(/{%-?\s*assign entries = include\.entries.*?%-?%}/, "")
            template_content = template_content.gsub(/{%\s*assign entries = include\.entries.*?%}/, "")
            template_content = template_content.gsub(/{%-?\s*for\s+post\s+in\s+entries\s*-?%}/, "{% for post in site.posts %}")
            template_content = template_content.gsub(/{%\s*for\s+post\s+in\s+entries\s*%}/, "{% for post in site.posts %}")
          end
        elsif include_hash.has_key?("collection")
          collection_name = include_hash["collection"]?

          coll_name = collection_name.try(&.as_s?)
          if coll_name
            template_content = template_content.gsub(/{%-?\s*assign entries = include\.entries.*?%-?%}/, "")
            template_content = template_content.gsub(/{%\s*assign entries = include\.entries.*?%}/, "")
            template_content = template_content.gsub(/{%-?\s*for\s+post\s+in\s+entries\s*-?%}/, "{% for post in site.collections.#{coll_name}.docs %}")
            template_content = template_content.gsub(/{%\s*for\s+post\s+in\s+entries\s*%}/, "{% for post in site.collections.#{coll_name}.docs %}")
          else
            template_content = template_content.gsub(/{%-?\s*assign entries = include\.entries.*?%-?%}/, "")
            template_content = template_content.gsub(/{%\s*assign entries = include\.entries.*?%}/, "")
            template_content = template_content.gsub(/{%-?\s*for\s+post\s+in\s+entries\s*-?%}/, "{% for post in site.posts %}")
            template_content = template_content.gsub(/{%\s*for\s+post\s+in\s+entries\s*%}/, "{% for post in site.posts %}")
          end
        end
      end

      template_content = template_content.gsub(/{%\s*continue\s*%}/, "")
      template_content = template_content.gsub(/\|\s*where_exp:\s*"[^"]*"\s*,\s*"[^"]*"(\s*%})/, "\\1")
      template_content = template_content.gsub(/\|\s*sort:\s*"[^"]*"(\s*%})/, "\\1")
      template_content = template_content.gsub(/\|\s*reverse(\s*%})/, "\\1")
      template_content = template_content.gsub(/\|\s*\|/, "|")
      template_content = template_content.gsub(/\|\s*(%})/, "\\1")
      template_content = template_content.gsub(/(\w+)\.last/, "\\1[1]")
      template_content = template_content.gsub(/({%\s*for\s+\w+\s+in\s+)\([^)]+\.\.[^)]+\)(\s*reversed)?(\s*%})/) do
        for_start = $1
        _reversed = $2?
        for_end = $3?
        "#{for_start}1..1#{_reversed}#{for_end}"
      end

      template_content
    end

    private def build_include_hash(node : Liquid::Block::JekyllInclude) : Hash(String, Liquid::Any)
      include_hash = {} of String => Liquid::Any

      if node.template_vars != nil
        node.template_vars.each do |key, value|
          evaluated = value.eval(@data)
          @data.set key, evaluated
          include_hash[key] = evaluated.is_a?(Liquid::Any) ? evaluated : Liquid::Any.new(evaluated)
        end
      end

      @data.set "include", Liquid::Any.new(include_hash)
      include_hash
    end

    private def get_template_filename(node : Liquid::Block::JekyllInclude, includes_dir : String) : String
      if File.exists?(File.join(includes_dir, node.template_name))
        File.join(includes_dir, node.template_name)
      elsif File.extname(node.template_name) == ".html"
        liquid_path = File.join(includes_dir, node.template_name.sub(/\.html$/, ".liquid"))
        File.exists?(liquid_path) ? liquid_path : File.join(includes_dir, node.template_name)
      elsif File.extname(node.template_name).empty?
        liquid_path = File.join(includes_dir, node.template_name + ".liquid")
        html_path = File.join(includes_dir, node.template_name + ".html")
        if File.exists?(liquid_path)
          liquid_path
        elsif File.exists?(html_path)
          html_path
        else
          File.join(includes_dir, node.template_name)
        end
      else
        File.join(includes_dir, node.template_name)
      end
    end

    def visit(node : Liquid::Block::JekyllInclude)
      base_path = get_base_path
      includes_dir = get_includes_dir(base_path)

      filename = get_template_filename(node, includes_dir)

      # Security: Validate the template file is within the includes directory
      safe_filename = Carafe::Security.sanitize_path(includes_dir, filename)
      if safe_filename.nil? || !File.exists?(safe_filename)
        @io << "<!-- Jekyll include blocked: path traversal or file not found --><!-- #{node.template_name} -->"
        return
      end

      include_hash = build_include_hash(node)

      template_content = File.read safe_filename
      template_content = process_template_content(template_content, include_hash)

      template = Template.parse template_content
      template.template_path = @template_path || "."
      @io << template.render(@data)
    end

    def visit(node : Liquid::Block::Highlight)
      content_io = IO::Memory.new
      node.children.each &.accept(RenderVisitor.new(@data, content_io, @template_path))
      code = content_io.to_s.strip

      begin
        html = Tartrazine.to_html(
          code,
          language: node.language,
          theme: "default",
          line_numbers: node.linenos?,
          standalone: false
        )

        @io << %(<figure class="highlight">)
        @io << %(<pre><code class="language-#{node.language}">)
        @io << html
        @io << %(</code></pre>)
        @io << %(</figure>)
      rescue
        @io << %(<figure class="highlight">)
        @io << %(<pre><code class="language-#{node.language}">)
        @io << HTML.escape(code)
        @io << %(</code></pre>)
        @io << %(</figure>)
      end
    end
  end
end

Liquid::BlockRegister.register "include", Liquid::Block::JekyllInclude, false
Liquid::BlockRegister.register "highlight", Liquid::Block::Highlight
