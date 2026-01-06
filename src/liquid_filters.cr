require "liquid"
require "markd"
require "html"

# Jekyll-compatible Liquid filters for carafe
module Carafe::LiquidFilters
  # Jekyll's markdownify filter - converts markdown to HTML
  #
  # Usage: {{ page.content | markdownify }}
  class Markdownify
    extend Liquid::Filters::Filter

    def self.filter(data : Liquid::Any, args : Array(Liquid::Any), options : Hash(String, Liquid::Any)) : Liquid::Any
      return Liquid::Any.new("") if data.raw.nil?

      # Convert input to string
      markdown_text = data.as_s

      # Use Markd to convert markdown to HTML
      html = Markd.to_html(markdown_text)

      Liquid::Any.new(html)
    end
  end

  # Jekyll's where_exp filter - filters array based on expression
  #
  # Usage: {{ array | where_exp: "item", "item.property == value" }}
  class WhereExp
    extend Liquid::Filters::Filter

    def self.filter(data : Liquid::Any, args : Array(Liquid::Any), options : Hash(String, Liquid::Any)) : Liquid::Any
      raise Liquid::FilterArgumentException.new("where_exp filter expects two arguments.") if args.size != 2

      item_var = args[0].to_s
      expression = args[1].to_s

      raw_data = data.raw

      # Return empty array if data is nil
      return Liquid::Any.new([] of Liquid::Any) if raw_data.nil?

      if raw_data.is_a?(Array)
        # Filter the array based on the expression
        filtered_array = raw_data.select do |item|
          evaluate_expression(item, item_var, expression)
        end

        # Convert to Array(Liquid::Any) if needed
        # If items are Hash, we need to wrap them
        converted_array = filtered_array.map do |item|
          item.is_a?(Liquid::Any) ? item : Liquid::Any.new(item)
        end

        # Return the filtered array wrapped in Liquid::Any
        Liquid::Any.new(converted_array)
      else
        # data is not an array, return it as-is
        data
      end
    end

    # Evaluate a simple expression against an item
    private def self.evaluate_expression(item, item_var : String, expression : String) : Bool
      # Parse simple expressions like:
      # - "item.property != false"
      # - "item.search != false"
      # - "item.title != null"

      # Extract property and comparison
      # Pattern: item.<property> <operator> <value>
      if expression.match(/^#{item_var}\.(\w+)\s*(!=|==|>=|<=|>|<)\s*(.+)$/)
        property = $1
        operator = $2
        value_str = $3

        # Get the property value from the item
        property_value = get_property_value(item, property)

        # Parse the comparison value
        comparison_value = parse_value(value_str)

        # Perform the comparison
        # For now, only handle != and == operators to avoid type issues
        case operator
        when "!="
          property_value != comparison_value
        when "=="
          property_value == comparison_value
        else
          # For other operators, try to compare as strings or return true
          begin
            property_value.to_s != comparison_value.to_s
          rescue
            true
          end
        end
      else
        # If we can't parse the expression, return true (include the item)
        true
      end
    end

    # Get a property value from an item (can be Hash, Liquid::Any, or Object)
    private def self.get_property_value(item, property : String)
      case item
      when Liquid::Any
        get_property_value(item.raw, property)
      when Hash
        if hash_value = item[property]?
          hash_value.is_a?(Liquid::Any) ? hash_value.raw : hash_value
        else
          nil
        end
      else
        nil
      end
    end

    # Parse a value string (handles "false", "true", "null", numbers, strings)
    private def self.parse_value(value_str : String)
      value_str = value_str.strip

      case value_str
      when "false"
        false
      when "true"
        true
      when "null", "nil"
        nil
      when /^\d+$/
        value_str.to_i
      when /^\d+\.\d+$/
        value_str.to_f
      else
        # Remove quotes if present
        if value_str.starts_with?('"') || value_str.starts_with?("'")
          value_str[1..-2]
        else
          value_str
        end
      end
    end
  end

  # Jekyll's date_to_string filter
  class DateToString
    extend Liquid::Filters::Filter

    def self.filter(data : Liquid::Any, args : Array(Liquid::Any), options : Hash(String, Liquid::Any)) : Liquid::Any
      return Liquid::Any.new("") if data.raw.nil?
      value = data.raw
      if value.is_a?(Time)
        Liquid::Any.new(value.to_s("%-d %b %Y"))
      else
        data
      end
    end
  end

  # Jekyll's slugify filter
  class Slugify
    extend Liquid::Filters::Filter

    def self.filter(data : Liquid::Any, args : Array(Liquid::Any), options : Hash(String, Liquid::Any)) : Liquid::Any
      return Liquid::Any.new("") if data.raw.nil?
      Liquid::Any.new(data.as_s.downcase.gsub(/([^\w_.]+)/, "-"))
    end
  end

  # Jekyll's relative_path filter
  class RelativePath
    extend Liquid::Filters::Filter

    def self.filter(data : Liquid::Any, args : Array(Liquid::Any), options : Hash(String, Liquid::Any)) : Liquid::Any
      return Liquid::Any.new("") if data.raw.nil?
      Liquid::Any.new(data.as_s)
    end
  end

  # Jekyll's relative_url filter
  class RelativeUrl
    extend Liquid::Filters::Filter

    def self.filter(data : Liquid::Any, args : Array(Liquid::Any), options : Hash(String, Liquid::Any)) : Liquid::Any
      return Liquid::Any.new("") if data.raw.nil?
      Liquid::Any.new(data.as_s)
    end
  end

  # Jekyll's absolute_url filter
  class AbsoluteUrl
    extend Liquid::Filters::Filter

    def self.filter(data : Liquid::Any, args : Array(Liquid::Any), options : Hash(String, Liquid::Any)) : Liquid::Any
      return Liquid::Any.new("") if data.raw.nil?
      Liquid::Any.new(data.as_s)
    end
  end

  # Jekyll's localize filter (passthrough)
  class Localize
    extend Liquid::Filters::Filter

    def self.filter(data : Liquid::Any, args : Array(Liquid::Any), options : Hash(String, Liquid::Any)) : Liquid::Any
      data
    end
  end

  # Jekyll's normalize_whitespace filter
  class NormalizeWhitespace
    extend Liquid::Filters::Filter

    def self.filter(data : Liquid::Any, args : Array(Liquid::Any), options : Hash(String, Liquid::Any)) : Liquid::Any
      return Liquid::Any.new("") if data.raw.nil?
      Liquid::Any.new(data.as_s.gsub(/\s+/, ' '))
    end
  end

  # Jekyll's newline_to_br filter
  class NewlineToBr
    extend Liquid::Filters::Filter

    def self.filter(data : Liquid::Any, args : Array(Liquid::Any), options : Hash(String, Liquid::Any)) : Liquid::Any
      return Liquid::Any.new("") if data.raw.nil?
      Liquid::Any.new(data.as_s.gsub(/\n/, "<br />\n"))
    end
  end

  # Jekyll's strip_html filter
  class StripHtml
    extend Liquid::Filters::Filter

    def self.filter(data : Liquid::Any, args : Array(Liquid::Any), options : Hash(String, Liquid::Any)) : Liquid::Any
      return Liquid::Any.new("") if data.raw.nil?
      Liquid::Any.new(data.as_s.gsub(/<[^>]*>/, ""))
    end
  end

  # Jekyll's strip_newlines filter
  class StripNewlines
    extend Liquid::Filters::Filter

    def self.filter(data : Liquid::Any, args : Array(Liquid::Any), options : Hash(String, Liquid::Any)) : Liquid::Any
      return Liquid::Any.new("") if data.raw.nil?
      Liquid::Any.new(data.as_s.gsub(/\n[\s]*/, ""))
    end
  end

  # Jekyll's truncatewords filter
  class Truncatewords
    extend Liquid::Filters::Filter

    def self.filter(data : Liquid::Any, args : Array(Liquid::Any), options : Hash(String, Liquid::Any)) : Liquid::Any
      return Liquid::Any.new("") if data.raw.nil?
      words = args[0]?.try(&.as_i) || 15
      Liquid::Any.new(data.as_s.split(/\s+/)[0, words].join(" "))
    end
  end

  # Jekyll's strip_index filter
  class StripIndex
    extend Liquid::Filters::Filter

    def self.filter(data : Liquid::Any, args : Array(Liquid::Any), options : Hash(String, Liquid::Any)) : Liquid::Any
      return Liquid::Any.new("") if data.raw.nil?
      Liquid::Any.new(data.as_s.sub(%r{/?index\.html?$}, "/"))
    end
  end

  # Jekyll's contains filter
  class Contains
    extend Liquid::Filters::Filter

    def self.filter(data : Liquid::Any, args : Array(Liquid::Any), options : Hash(String, Liquid::Any)) : Liquid::Any
      return Liquid::Any.new(false) if data.raw.nil?
      return Liquid::Any.new(false) if args.empty?
      search = args[0].as_s
      Liquid::Any.new(data.as_s.includes?(search))
    end
  end

  # Jekyll's rstrip filter
  class Rstrip
    extend Liquid::Filters::Filter

    def self.filter(data : Liquid::Any, args : Array(Liquid::Any), options : Hash(String, Liquid::Any)) : Liquid::Any
      return Liquid::Any.new("") if data.raw.nil?
      Liquid::Any.new(data.as_s.rstrip)
    end
  end

  # Jekyll's lstrip filter
  class Lstrip
    extend Liquid::Filters::Filter

    def self.filter(data : Liquid::Any, args : Array(Liquid::Any), options : Hash(String, Liquid::Any)) : Liquid::Any
      return Liquid::Any.new("") if data.raw.nil?
      Liquid::Any.new(data.as_s.lstrip)
    end
  end

  # Jekyll's strip filter
  class Strip
    extend Liquid::Filters::Filter

    def self.filter(data : Liquid::Any, args : Array(Liquid::Any), options : Hash(String, Liquid::Any)) : Liquid::Any
      return Liquid::Any.new("") if data.raw.nil?
      Liquid::Any.new(data.as_s.strip)
    end
  end

  # Jekyll's split filter
  class Split
    extend Liquid::Filters::Filter

    def self.filter(data : Liquid::Any, args : Array(Liquid::Any), options : Hash(String, Liquid::Any)) : Liquid::Any
      return Liquid::Any.new([] of Liquid::Any) if data.raw.nil?
      pattern = args[0]?.try(&.as_s) || " "
      array = data.as_s.split(pattern).map { |s| Liquid::Any.new(s) }
      Liquid::Any.new(array)
    end
  end

  # Jekyll's times filter
  class Times
    extend Liquid::Filters::Filter

    def self.filter(data : Liquid::Any, args : Array(Liquid::Any), options : Hash(String, Liquid::Any)) : Liquid::Any
      return Liquid::Any.new("") if data.raw.nil?
      count = args[0]?.try(&.as_i) || 1
      return Liquid::Any.new("") if count <= 0
      Liquid::Any.new(data.as_s * count)
    end
  end

  # Jekyll's slice filter
  class Slice
    extend Liquid::Filters::Filter

    def self.filter(data : Liquid::Any, args : Array(Liquid::Any), options : Hash(String, Liquid::Any)) : Liquid::Any
      return Liquid::Any.new("") if data.raw.nil?
      start = args[0]?.try(&.as_i) || 0
      length = args[1]?.try(&.as_i) || 1
      str = data.as_s
      return Liquid::Any.new("") if start < 0 || start >= str.size
      Liquid::Any.new(str[start, length])
    end
  end

  # Jekyll's minus filter
  class Minus
    extend Liquid::Filters::Filter

    def self.filter(data : Liquid::Any, args : Array(Liquid::Any), options : Hash(String, Liquid::Any)) : Liquid::Any
      return Liquid::Any.new(0) if data.raw.nil?
      value = args[0]?.try(&.as_i) || 0
      Liquid::Any.new(data.as_i - value)
    end
  end

  # Jekyll's escape_once filter
  class EscapeOnce
    extend Liquid::Filters::Filter

    def self.filter(data : Liquid::Any, args : Array(Liquid::Any), options : Hash(String, Liquid::Any)) : Liquid::Any
      return Liquid::Any.new("") if data.raw.nil?
      Liquid::Any.new(HTML.escape(data.as_s))
    end
  end

  # Jekyll's striptags filter
  class Striptags
    extend Liquid::Filters::Filter

    def self.filter(data : Liquid::Any, args : Array(Liquid::Any), options : Hash(String, Liquid::Any)) : Liquid::Any
      return Liquid::Any.new("") if data.raw.nil?
      str = data.as_s
      return Liquid::Any.new("") if str.empty?
      begin
        Liquid::Any.new(str.gsub(/<[^>]*>/, "").gsub(/\s+/, " ").strip)
      rescue
        Liquid::Any.new(str)
      end
    end
  end

  # Jekyll's xml_escape filter
  class XmlEscape
    extend Liquid::Filters::Filter

    def self.filter(data : Liquid::Any, args : Array(Liquid::Any), options : Hash(String, Liquid::Any)) : Liquid::Any
      Liquid::Any.new(HTML.escape(data.as_s))
    end
  end

  # Jekyll's date_to_xmlschema filter
  class DateToXmlschema
    extend Liquid::Filters::Filter

    def self.filter(data : Liquid::Any, args : Array(Liquid::Any), options : Hash(String, Liquid::Any)) : Liquid::Any
      time = if data.raw.is_a?(Time)
                data.raw.as(Time)
              elsif data.raw.is_a?(String)
                date_str = data.as_s
                begin
                  Time.parse_rfc3339(date_str)
                rescue
                  begin
                    Time.parse_iso8601(date_str)
                  rescue
                    Time.parse(date_str, "%Y-%m-%d", Time::Location.local)
                  end
                end
              else
                Time.local
              end
      Liquid::Any.new(time.to_rfc3339)
    end
  end

  # Register all filters with Liquid
  Liquid::Filters::FilterRegister.register "markdownify", Carafe::LiquidFilters::Markdownify
  Liquid::Filters::FilterRegister.register "where_exp", Carafe::LiquidFilters::WhereExp
  Liquid::Filters::FilterRegister.register "date_to_string", Carafe::LiquidFilters::DateToString
  Liquid::Filters::FilterRegister.register "slugify", Carafe::LiquidFilters::Slugify
  Liquid::Filters::FilterRegister.register "relative_path", Carafe::LiquidFilters::RelativePath
  Liquid::Filters::FilterRegister.register "relative_url", Carafe::LiquidFilters::RelativeUrl
  Liquid::Filters::FilterRegister.register "absolute_url", Carafe::LiquidFilters::AbsoluteUrl
  Liquid::Filters::FilterRegister.register "localize", Carafe::LiquidFilters::Localize
  Liquid::Filters::FilterRegister.register "normalize_whitespace", Carafe::LiquidFilters::NormalizeWhitespace
  Liquid::Filters::FilterRegister.register "newline_to_br", Carafe::LiquidFilters::NewlineToBr
  Liquid::Filters::FilterRegister.register "strip_html", Carafe::LiquidFilters::StripHtml
  Liquid::Filters::FilterRegister.register "strip_newlines", Carafe::LiquidFilters::StripNewlines
  Liquid::Filters::FilterRegister.register "truncatewords", Carafe::LiquidFilters::Truncatewords
  Liquid::Filters::FilterRegister.register "strip_index", Carafe::LiquidFilters::StripIndex
  Liquid::Filters::FilterRegister.register "contains", Carafe::LiquidFilters::Contains
  Liquid::Filters::FilterRegister.register "rstrip", Carafe::LiquidFilters::Rstrip
  Liquid::Filters::FilterRegister.register "lstrip", Carafe::LiquidFilters::Lstrip
  Liquid::Filters::FilterRegister.register "strip", Carafe::LiquidFilters::Strip
  Liquid::Filters::FilterRegister.register "split", Carafe::LiquidFilters::Split
  Liquid::Filters::FilterRegister.register "times", Carafe::LiquidFilters::Times
  Liquid::Filters::FilterRegister.register "slice", Carafe::LiquidFilters::Slice
  Liquid::Filters::FilterRegister.register "minus", Carafe::LiquidFilters::Minus
  Liquid::Filters::FilterRegister.register "escape_once", Carafe::LiquidFilters::EscapeOnce
  Liquid::Filters::FilterRegister.register "striptags", Carafe::LiquidFilters::Striptags
  Liquid::Filters::FilterRegister.register "xml_escape", Carafe::LiquidFilters::XmlEscape
  Liquid::Filters::FilterRegister.register "date_to_xmlschema", Carafe::LiquidFilters::DateToXmlschema
end
