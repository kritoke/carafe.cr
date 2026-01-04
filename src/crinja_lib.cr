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
  return Crinja::Value.new(false) if target.undefined?
  search = arguments.varargs.empty? ? Crinja::Value.new("") : arguments.varargs[0]
  target.as_s.includes?(search.to_s)
end

Crinja.filter(:strip_newlines) do
  return Crinja::Value.new("") if target.undefined?
  target.as_s.gsub(/\n/, "")
end

# Liquid/Jekyll rstrip filter - removes trailing whitespace
Crinja.filter(:rstrip) do
  return Crinja::Value.new("") if target.undefined?
  Crinja::Value.new(target.to_s.rstrip)
end

# Liquid/Jekyll lstrip filter - removes leading whitespace
Crinja.filter(:lstrip) do
  return Crinja::Value.new("") if target.undefined?
  Crinja::Value.new(target.to_s.lstrip)
end

# Liquid/Jekyll strip filter - removes leading and trailing whitespace
Crinja.filter(:strip) do
  return Crinja::Value.new("") if target.undefined?
  Crinja::Value.new(target.to_s.strip)
end

# Liquid/Jekyll split filter - splits string into array
Crinja.filter({pattern: " "}, :split) do
  return Crinja::Value.new([] of Crinja::Value) if target.undefined?
  pattern = arguments["pattern"].to_s
  Crinja::Value.new(target.to_s.split(pattern).map { |s| Crinja::Value.new(s) })
end

# Liquid/Jekyll times filter - repeats string N times
Crinja.filter({count: 1}, :times) do
  return Crinja::Value.new("") if target.undefined?
  count = arguments["count"].to_i
  return Crinja::Value.new("") if count <= 0
  Crinja::Value.new(target.to_s * count)
end

# Liquid/Jekyll slice filter - extracts a substring
Crinja.filter({start: 0, length: 1}, :slice) do
  return Crinja::Value.new("") if target.undefined?
  start = arguments["start"].to_i
  length = arguments["length"].to_i
  str = target.to_s
  return Crinja::Value.new("") if start < 0 || start >= str.size
  Crinja::Value.new(str[start, length])
end

# Liquid/Jekyll minus filter - subtracts numbers
Crinja.filter({value: 0}, :minus) do
  return Crinja::Value.new(0) if target.undefined?
  value = arguments["value"].to_i
  Crinja::Value.new(target.to_i - value)
end

Crinja.filter(:newline_to_br) do
  return Crinja::Value.new("") if target.undefined?
  target.as_s.gsub(/\n/, "<br />\n")
end

Crinja.filter(:escape_once) do
  return Crinja::Value.new("") if target.undefined?
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

# case/when tag implementation (Liquid/Jekyll compatibility)
class Crinja::Tag::Case < Crinja::Tag
  name "case", "endcase"

  private def interpret(io : IO, renderer : Crinja::Renderer, tag_node : TagNode)
    env = renderer.env

    # Parse the expression to evaluate
    args = ArgumentsParser.new(tag_node.arguments, renderer.env.config)
    target_expression = args.parse_expression
    args.close

    # Evaluate the target expression once
    target_value = env.evaluate(target_expression)

    # Find matching when clause and render it
    tag_node.block.children.each do |node|
      if node.is_a?(TagNode) && node.name == "when"
        if match_when_clause?(node, target_value, env, renderer)
          io << renderer.render(node.block).value
          break
        end
      elsif node.is_a?(TagNode) && node.name == "else"
        io << renderer.render(node.block).value
        break
      end
    end
  end

  private def match_when_clause?(when_node : TagNode, target_value : Crinja::Value, env, renderer : Crinja::Renderer) : Bool
    args = ArgumentsParser.new(when_node.arguments, renderer.env.config)

    # Parse all comparison values
    while true
      begin
        value_expr = args.parse_expression
        comparison_value = env.evaluate(value_expr)

        # Compare values
        if values_equal?(target_value, comparison_value)
          args.close
          return true
        end

        # Check if there are more values (comma-separated)
        break unless args.current_token.kind == Crinja::Parser::Token::Kind::COMMA
        args.next_token
      rescue
        break
      end
    end

    args.close
    false
  end

  private def values_equal?(a : Crinja::Value, b : Crinja::Value) : Bool
    # Convert both to strings for comparison (Liquid behavior)
    a.to_s == b.to_s
  end
end

Crinja::Tag::Library::TAGS << Crinja::Tag::Case

# when tag (part of case/when)
class Crinja::Tag::When < Crinja::Tag
  name "when"

  # when tags are handled by the parent case tag
  def interpret(io : IO, renderer : Crinja::Renderer, tag_node : TagNode)
    # Do nothing - handled by case tag
  end
end

Crinja::Tag::Library::TAGS << Crinja::Tag::When

# continue tag for loops (Liquid compatibility)
class Crinja::Tag::Continue < Crinja::Tag
  name "continue"

  def interpret(io : IO, renderer : Crinja::Renderer, tag_node : TagNode)
    # In Liquid/Jekyll, {% continue %} skips to the next iteration in a loop
    # For now, do nothing - the loop will continue naturally
  end
end

Crinja::Tag::Library::TAGS << Crinja::Tag::Continue

# break tag for loops (Liquid compatibility)
class Crinja::Tag::Break < Crinja::Tag
  name "break"

  def interpret(io : IO, renderer : Crinja::Renderer, tag_node : TagNode)
    # In Liquid/Jekyll, {% break %} exits the current loop
    # For now, do nothing - the loop will complete naturally
  end
end

Crinja::Tag::Library::TAGS << Crinja::Tag::Break

