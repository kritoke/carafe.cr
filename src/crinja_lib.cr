require "crinja"
require "html"

Crinja.filter(:date_to_string) do
  value = target.raw
  if value.is_a?(Time)
    Crinja::Value.new(value.to_s("%-d %b %Y"))
  else
    target
  end
end

Crinja.filter(:markdownify) do
  Crinja::SafeString.new(Markd.to_html(target.to_s))
end

Crinja.filter(:slugify) do
  Crinja::Value.new(target.to_s.downcase.gsub(/([^\w_.]+)/, '-'))
end

Crinja.filter(:relative_path) do
  return Crinja::Value.new("") if target.undefined?
  Crinja::Value.new(target.to_s)
end

Crinja.filter(:relative_url) do
  return Crinja::Value.new("") if target.undefined?
  Crinja::Value.new(target.to_s)
end

Crinja.filter(:absolute_url) do
  return Crinja::Value.new("") if target.undefined?
  Crinja::Value.new(target.to_s)
end

Crinja.filter(:localize) do
  target
end

Crinja.filter(:normalize_whitespace) do
  return Crinja::Value.new("") if target.undefined?
  Crinja::Value.new(target.as_s.gsub(/\s+/, ' '))
end

# Jekyll filter: newline_to_br
Crinja.filter(:newline_to_br) do
  return Crinja::Value.new("") if target.undefined?
  Crinja::Value.new(target.to_s.gsub(/\n/, "<br />\n"))
end

# Jekyll filter: strip_html
Crinja.filter(:strip_html) do
  return Crinja::Value.new("") if target.undefined?
  # Simple HTML stripping - remove HTML tags
  Crinja::Value.new(target.to_s.gsub(/<[^>]*>/, ""))
end

# Jekyll filter: strip_newlines
Crinja.filter(:strip_newlines) do
  return Crinja::Value.new("") if target.undefined?
  Crinja::Value.new(target.to_s.gsub(/\n[\s]*/, ""))
end

# Jekyll filter: truncatewords
Crinja.filter({words: 15}, :truncatewords) do
  return Crinja::Value.new("") if target.undefined?
  words = arguments["words"].to_i
  Crinja::Value.new(target.to_s.split(/\s+/)[0, words].join(" "))
end

Crinja.filter(:strip_index) do
  return Crinja::Value.new("") if target.undefined?
  Crinja::Value.new(target.as_s.sub(%r{/?index\.html?$}, "/"))
end


Crinja.filter(:contains) do
  search = arguments.varargs.empty? ? Crinja::Value.new("") : arguments.varargs[0]
  target.as_s.includes?(search.to_s)
end

Crinja.filter(:strip_newlines) do
  target.as_s.gsub(/\n/, "")
end

Crinja.filter(:strip) do
  target.as_s.strip
end

Crinja.filter(:newline_to_br) do
  target.as_s.gsub(/\n/, "<br />\n")
end

Crinja.filter(:escape_once) do
  HTML.escape(target.as_s)
end

# Override striptags filter (aliased as strip_html) to handle empty strings
Crinja.filter(:striptags) do
  str = target.to_s
  return Crinja::Value.new("") if str.empty?
  begin
    # Simple HTML tag stripping - remove everything between < and >
    Crinja::Value.new(str.gsub(/<[^>]*>/, "").gsub(/\s+/, " ").strip)
  rescue
    Crinja::Value.new(str)
  end
end

Crinja.filter(:xml_escape) do
  Crinja::SafeString.new(HTML.escape(target.as_s))
end

Crinja.filter(:date_to_xmlschema) do
  time = if target.raw.is_a?(Time)
            target.raw.as(Time)
          elsif target.raw.is_a?(String)
            # Try to parse common date formats
            date_str = target.as_s
            begin
              Time.parse_rfc3339(date_str)
            rescue
              begin
                Time.parse_iso8601(date_str)
              rescue
                # If all else fails, try the format used in posts
                Time.parse(date_str, "%Y-%m-%d", Time::Location.local)
              end
            end
          else
            Time.local
          end
  time.to_rfc3339
end

class Crinja::Tag::Unless < Crinja::Tag::If
  name "unless", "endunless"

  private def interpret(io : IO, renderer : Crinja::Renderer, tag_node : TagNode)
    env = renderer.env
    current_branch_active = !evaluate_node(tag_node, env)

    tag_node.block.children.each do |node|
      if (tnode = node).is_a?(TagNode) && tnode.name == "else"
        break if current_branch_active

        current_branch_active = true
      else
        renderer.render(node).value(io) if current_branch_active
      end
    end
  end
end

Crinja::Tag::Library::TAGS << Crinja::Tag::Unless

class Crinja::Tag::Assign < Crinja::Tag::Set
  name "assign"
end

Crinja::Tag::Library::TAGS << Crinja::Tag::Assign

class Crinja::Tag::Highlight < Crinja::Tag
  name "highlight", "endhighlight"

  private def interpret(io : IO, renderer : Crinja::Renderer, tag_node : TagNode)
    args = ArgumentsParser.new(tag_node.arguments, renderer.env.config)

    io << %(<figure class="highlight"><pre><code)
    unless args.current_token.kind.eof?
      language = args.current_token.value
      io << %( class="language-#{language}" data-lang="#{language}")
      # Consume the language token
      args.next_token

      # Support additional options like "lineos" - these can be added as data attributes
      # For now, just consume them silently
      while !args.current_token.kind.eof?
        args.next_token
      end
    end
    io << %(>)
    io << Crinja::SafeString.new(renderer.render(tag_node.block).value.chomp)
    io << %(</code></pre></figure>)
  end
end

Crinja::Tag::Library::TAGS << Crinja::Tag::Highlight

# Liquid/Jekyll compatibility: capture tag
# Captures the output of a block into a variable
class Crinja::Tag::Capture < Crinja::Tag
  name "capture", "endcapture"

  private def interpret(io : IO, renderer : Crinja::Renderer, tag_node : TagNode)
    env = renderer.env

    # Parse the variable name from arguments
    args = ArgumentsParser.new(tag_node.arguments, renderer.env.config)
    var_name = args.parse_expression
    args.close

    # Capture the block output
    captured_output = String.build do |str_io|
      renderer.render(tag_node.block).value(str_io)
    end

    # Store the captured output in the context
    env.context[var_name.to_s] = Crinja::Value.new(captured_output.strip)
  end
end

Crinja::Tag::Library::TAGS << Crinja::Tag::Capture
