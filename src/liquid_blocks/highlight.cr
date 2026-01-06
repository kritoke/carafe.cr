require "liquid"
require "liquid/context"
require "tartrazine"

module Liquid::Block
  class Highlight < BeginBlock
    getter language : String
    getter linenos : Bool

    def initialize(content : String)
      # Parse arguments: language linenos
      parts = content.strip.split
      @language = parts.first? || "text"
      @linenos = parts.includes?("linenos") || parts.includes?("lineos")
    end
  end
end

module Liquid
  class RenderVisitor < Visitor
    def visit(node : Liquid::Block::Highlight)
      # Collect the content from child nodes
      content_io = IO::Memory.new
      node.children.each &.accept(RenderVisitor.new(@data, content_io, @template_path))
      code = content_io.to_s.strip

      begin
        # Use tartrazine to highlight the code
        # Using the high-level API: Tartrazine.to_html
        html = Tartrazine.to_html(
          code,
          language: node.language,
          theme: "default",  # Can be configured later
          line_numbers: node.linenos,
          standalone: false  # We'll wrap it ourselves
        )

        # Wrap in figure element (Jekyll-compatible structure)
        @io << %(<figure class="highlight">)
        @io << %(<pre><code class="language-#{node.language}">)
        @io << html
        @io << %(</code></pre>)
        @io << %(</figure>)
      rescue ex
        # If highlighting fails, fall back to plain code block
        @io << %(<figure class="highlight">)
        @io << %(<pre><code class="language-#{node.language}">)
        @io << HTML.escape(code)
        @io << %(</code></pre>)
        @io << %(</figure>)
      end
    end
  end
end

# Register the highlight block with Liquid
Liquid::BlockRegister.register "highlight", Liquid::Block::Highlight
