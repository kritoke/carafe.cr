require "string_scanner"

module Carafe::JekyllCompat
  # Token types for Liquid template parsing
  
  # Base token for template elements
  abstract struct Token
    property content : String
    
    def initialize(@content : String)
    end
    
    abstract def tag_name : String?
    abstract def args : String?
  end
  
  # A raw text segment (not Liquid syntax)
  struct TextToken < Token
    def initialize(@content : String)
      super(@content)
    end
    
    def tag_name : Nil
      nil
    end
    
    def args : Nil
      nil
    end
  end
  
  # {% tag_name args %}
  struct LiquidTagToken < Token
    getter tag : String
    getter raw_args : String
    
    def initialize(@tag : String, @raw_args : String, content : String)
      super(content)
    end
    
    def tag_name : String
      @tag
    end
    
    def args : String
      @raw_args
    end
  end
  
  # {{ expression }}
  struct OutputToken < Token
    getter expression : String
    
    def initialize(@expression : String, content : String)
      super(content)
    end
    
    def tag_name : Nil
      nil
    end
    
    def args : Nil
      nil
    end
  end
  
  # Tokenizer that breaks Liquid templates into meaningful chunks
  # Uses StringScanner for efficient position tracking
  # Minimal regex usage - prefers string operations where possible
  module Tokenizer
    extend self
    
    # Tokenize a template string into tokens
    def tokenize(template : String) : Array(Token)
      tokens = [] of Token
      scanner = StringScanner.new(template)
      
      while !scanner.eos?
        rest = scanner.rest
        
        if rest.starts_with?("{{")
          tokens << scan_output(scanner)
        elsif rest.starts_with?("{%")
          tokens << scan_liquid_tag(scanner)
        else
          tokens << scan_text(scanner)
        end
      end
      
      tokens
    end
    
    private def scan_output(scanner : StringScanner) : OutputToken
      # Skip {{
      pos = scanner.offset
      scanner.offset = pos + 2
      
      # Skip whitespace
      while !scanner.eos? && scanner.rest[0]?.try(&.whitespace?)
        scanner.offset += 1
      end
      
      # Read until }}
      expr_start = scanner.offset
      while !scanner.eos? && scanner.rest.starts_with?("}}") == false
        scanner.offset += 1
      end
      expression = scanner.string[expr_start...scanner.offset].strip
      
      # Capture content including delimiters
      content = scanner.string[pos...scanner.offset + 2]
      
      # Skip }}
      scanner.offset += 2 unless scanner.eos?
      
      OutputToken.new(expression, content)
    end
    
    private def scan_liquid_tag(scanner : StringScanner) : LiquidTagToken
      # Skip {%
      pos = scanner.offset
      scanner.offset = pos + 2
      
      # Skip whitespace
      while !scanner.eos? && scanner.rest[0]?.try(&.whitespace?)
        scanner.offset += 1
      end
      
      # Read tag content until %}
      tag_start = scanner.offset
      while !scanner.eos? && scanner.rest.starts_with?("%}") == false
        scanner.offset += 1
      end
      
      tag_content = scanner.string[tag_start...scanner.offset]
      
      # Capture content including delimiters
      content = scanner.string[pos...scanner.offset + 2]
      
      # Skip %}
      scanner.offset += 2 unless scanner.eos?
      
      # Parse tag name and args
      parts = tag_content.strip.split(' ', limit: 2)
      tag_name = parts[0]? || ""
      args = parts[1]? || ""
      
      LiquidTagToken.new(tag_name, args, content)
    end
    
    private def scan_text(scanner : StringScanner) : TextToken
      # Use rest to grab all text until next tag
      rest = scanner.rest
      next_tag = find_next_tag(rest)
      
      if next_tag
        # Grab text up to the tag
        text = rest[0...next_tag]
        scanner.offset += next_tag
      else
        # Grab remaining text
        text = rest
        scanner.offset = scanner.string.size
      end
      
      TextToken.new(text)
    end
    
    # Find position of next {{ or {%
    private def find_next_tag(str : String) : Int32?
      brace_pos = str.index("{{")
      tag_pos = str.index("{%")
      
      return brace_pos if brace_pos && !tag_pos
      return tag_pos if tag_pos && !brace_pos
      return nil unless brace_pos && tag_pos
      
      # Both exist - return the smaller one
      brace_pos < tag_pos ? brace_pos : tag_pos
    end
    
    # Check if character is a digit
    private def digit?(c : Char) : Bool
      c >= '0' && c <= '9'
    end
  end
  
  # Preprocessor that transforms Liquid templates
  module Preprocessor
    extend self
    
    # Check if character is a digit
    private def digit?(c : Char) : Bool
      c >= '0' && c <= '9'
    end
    
    # Process a template, transforming unsupported Liquid syntax
    def preprocess(template : String) : String
      tokens = Tokenizer.tokenize(template)
      
      tokens.map { |token| transform_token(token) }.join
    end
    
    private def transform_token(token : Token) : String
      case token
      when LiquidTagToken
        transform_liquid_tag(token)
      when OutputToken
        transform_output(token)
      else
        token.content
      end
    end
    
    private def transform_liquid_tag(tag : LiquidTagToken) : String
      case tag.tag_name
      when "for"
        transform_for_tag(tag)
      when "assign"
        transform_assign_tag(tag)
      when "continue"
        # Remove {% continue %} - not supported
        ""
      else
        tag.content
      end
    end
    
    # Transform {% for var in collection ... %} to remove unsupported modifiers
    private def transform_for_tag(tag : LiquidTagToken) : String
      args = tag.args
      
      # Remove offset:N, limit:N, and reversed
      args = remove_for_modifier(args, "offset:")
      args = remove_for_modifier(args, "limit:")
      args = remove_for_modifier(args, "reversed")
      
      # Clean up extra whitespace but preserve structure
      args = collapse_tag_whitespace(args)
      args = args.rstrip
      
      "{% for #{args} %}"
    end
    
    private def remove_for_modifier(args : String, modifier : String) : String
      idx = args.index(modifier)
      return args unless idx
      
      # Find where the modifier value starts (after colon for offset:/limit:)
      end_idx = idx + modifier.size
      
      if modifier.ends_with?(":")
        # Skip whitespace after colon
        while end_idx < args.size && args[end_idx] == ' '
          end_idx += 1
        end
        
        # Skip the value (digits for offset:/limit:)
        while end_idx < args.size && digit?(args[end_idx])
          end_idx += 1
        end
      else
        # For modifiers like 'reversed', find the end of the word
        while end_idx < args.size && args[end_idx] != ' '
          end_idx += 1
        end
      end
      
      # Skip trailing whitespace
      while end_idx < args.size && args[end_idx] == ' '
        end_idx += 1
      end
      
      # Recombine without this modifier
      before = args[0...idx]
      after = end_idx < args.size ? args[end_idx..] : ""
      new_args = before + after
      
      # Recursively check for more occurrences
      if new_args.includes?(modifier)
        new_args = remove_for_modifier(new_args, modifier)
      end
      
      new_args
    end
    
    # Transform {% assign var = value | unsupported_filter %} to remove filters
    private def transform_assign_tag(tag : LiquidTagToken) : String
      args = tag.args
      
      args = remove_filter(args, "where_exp:")
      args = remove_filter(args, "sort:")
      args = remove_filter(args, "reverse")
      
      args = collapse_tag_whitespace(args)
      args = args.rstrip
      
      "{% assign #{args} %}"
    end
    
    private def remove_filter(args : String, filter_name : String) : String
      # Look for | filter_name (with optional space after pipe)
      pipe_idx = args.index("|")
      return args unless pipe_idx
      
      # Check if followed by optional space and the filter name
      check_idx = pipe_idx + 1
      while check_idx < args.size && args[check_idx] == ' '
        check_idx += 1
      end
      
      # Check if this is our filter
      filter_start = check_idx
      filter_end_check = check_idx
      while filter_end_check < args.size && args[filter_end_check] != ' ' && args[filter_end_check] != '%' && args[filter_end_check] != '|'
        filter_end_check += 1
      end
      found_filter = args[filter_start...filter_end_check]
      
      # Also try with space (| sort: vs |sort:)
      filter_with_space = " #{filter_name}"
      filter_without_space = filter_name
      
      unless found_filter == filter_with_space || found_filter == filter_without_space
        # Not our filter, look for next pipe
        next_pipe = args.index("|", pipe_idx + 1)
        return args unless next_pipe
        
        # Recursively check from next pipe
        remaining = args[next_pipe..]
        new_remaining = remove_filter(remaining, filter_name)
        return args[0...next_pipe] + new_remaining
      end
      
      # Found our filter - skip past it
      filter_end = filter_start
      while filter_end < args.size && args[filter_end] != ' ' && args[filter_end] != '%' && args[filter_end] != '|'
        filter_end += 1
      end
      
      # Handle quoted arguments (e.g., sort: "title")
      while filter_end < args.size && args[filter_end] == ' '
        filter_end += 1
      end
      
      if filter_end < args.size && args[filter_end] == '"'
        filter_end += 1
        while filter_end < args.size && args[filter_end] != '"'
          filter_end += 1
        end
        filter_end += 1 if filter_end < args.size  # closing quote
        
        # Handle comma-separated arguments (e.g., where_exp: "item", "expr")
        while filter_end < args.size && (args[filter_end] == ',' || args[filter_end] == ' ')
          filter_end += 1
        end
        
        # Handle additional quoted argument
        if filter_end < args.size && args[filter_end] == '"'
          filter_end += 1
          while filter_end < args.size && args[filter_end] != '"'
            filter_end += 1
          end
          filter_end += 1 if filter_end < args.size  # closing quote
        end
      end
      
      # Recombine without this filter
      before = args[0...pipe_idx]
      after = filter_end < args.size ? args[filter_end..] : ""
      new_args = before + after
      
      # Recursively check for more filters
      if new_args.includes?("|") && new_args.includes?(filter_name)
        new_args = remove_filter(new_args, filter_name)
      end
      
      new_args
    end
    
    private def transform_output(tag : OutputToken) : String
      expr = tag.expression
      
      expr = transform_dot_accessor(expr, "last", "1")
      expr = transform_dot_accessor(expr, "first", "0")
      
      "{{ #{expr} }}"
    end
    
    private def transform_dot_accessor(expr : String, method : String, index : String) : String
      search = ".#{method}"
      return expr unless expr.includes?(search)
      
      idx = expr.index(search)
      return expr unless idx
      
      # Check: is this a method call or part of a longer identifier?
      # We transform when followed by whitespace, }, |, etc.
      # We DON'T transform when followed by alphanumeric (like .lastname)
      end_idx = idx + search.size
      if end_idx < expr.size
        next_char = expr[end_idx]
        return expr if next_char.alphanumeric?
      end
      
      var_name = expr[0...idx]
      "#{var_name}[#{index}]"
    end
    
    private def collapse_tag_whitespace(text : String) : String
      # Early return if no multiple whitespace
      return text unless text.includes?("  ")
      
      result = text.dup
      idx = 0
      while idx < result.size
        if result[idx] == ' ' || result[idx] == '\t'
          # Skip all consecutive whitespace
          start = idx
          idx += 1
          while idx < result.size && (result[idx] == ' ' || result[idx] == '\t')
            idx += 1
          end
          # Only replace if we found multiple whitespace chars
          if idx > start + 1
            result = result[0...start] + " " + result[idx..]
            idx = start + 1
          end
        else
          idx += 1
        end
      end
      result
    end
  end
end