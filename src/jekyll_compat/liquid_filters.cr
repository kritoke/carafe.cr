require "liquid"
require "markd"
require "html"

module Carafe::JekyllCompat
  module LiquidFilters
    extend self

    @@site_url : String = ""
    @@baseurl : String = ""

    def site_url=(url : String)
      @@site_url = url
    end

    def baseurl=(url : String)
      @@baseurl = url
    end

    def baseurl
      @@baseurl
    end

    def register_all!
      register("markdownify", Markdownify)
      register("where_exp", WhereExp)
      register("jsonify", Jsonify)
      register("date_to_string", DateToString)
      register("date_to_xmlschema", DateToXmlschema)
      register("slugify", Slugify)
      register("relative_path", RelativePath)
      register("relative_url", RelativeUrl)
      register("absolute_url", AbsoluteUrl)
      register("localize", Localize)
      register("normalize_whitespace", NormalizeWhitespace)
      register("newline_to_br", NewlineToBr)
      register("strip_html", StripHtml)
      register("strip_newlines", StripNewlines)
      register("truncatewords", Truncatewords)
      register("strip_index", StripIndex)
      register("contains", Contains)
      register("rstrip", Rstrip)
      register("lstrip", Lstrip)
      register("strip", Strip)
      register("split", Split)
      register("times", Times)
      register("slice", Slice)
      register("minus", Minus)
      register("escape_once", EscapeOnce)
      register("striptags", Striptags)
      register("xml_escape", XmlEscape)
    end

    private def register(name : String, klass)
      Liquid::Filters::FilterRegister.register name, klass
    end

    class Markdownify
      extend Liquid::Filters::Filter

      def self.filter(data : Liquid::Any, args : Array(Liquid::Any), options : Hash(String, Liquid::Any)) : Liquid::Any
        return Liquid::Any.new("") if data.raw.nil?
        Liquid::Any.new(Markd.to_html(data.as_s))
      end
    end

    class WhereExp
      extend Liquid::Filters::Filter

      def self.filter(data : Liquid::Any, args : Array(Liquid::Any), options : Hash(String, Liquid::Any)) : Liquid::Any
        return Liquid::Any.new([] of Liquid::Any) if data.raw.nil?
        raise Liquid::FilterArgumentException.new("where_expects two arguments.") if args.size != 2

        item_var = args[0].to_s
        expression = args[1].to_s

        raw_data = data.raw
        return Liquid::Any.new([] of Liquid::Any) unless raw_data.is_a?(Array)

        filtered_array = raw_data.select do |item|
          evaluate_expression(item, item_var, expression)
        end

        converted_array = filtered_array.map do |item|
          item.is_a?(Liquid::Any) ? item : Liquid::Any.new(item)
        end

        Liquid::Any.new(converted_array)
      end

      private def self.evaluate_expression(item, item_var : String, expression : String) : Bool
        if expression.match(/^#{item_var}\.(\w+)\s*(!=|==|>=|<=|>|<)\s*(.+)$/)
          property = $1
          operator = $2
          value_str = $3

          property_value = get_property_value(item, property)
          comparison_value = parse_value(value_str)

          case operator
          when "!="
            property_value != comparison_value
          when "=="
            property_value == comparison_value
          else
            begin
              property_value.to_s != comparison_value.to_s
            rescue
              true
            end
          end
        else
          true
        end
      end

      private def self.get_property_value(item, property : String)
        case item
        when Liquid::Any
          get_property_value(item.raw, property)
        when Hash
          if hash_value = item[property]?
            hash_value.is_a?(Liquid::Any) ? hash_value.raw : hash_value
          end
        end
      end

      private def self.parse_value(value_str : String)
        case value_str.strip
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
          stripped = value_str.strip
          if stripped.starts_with?('"') || stripped.starts_with?("'")
            stripped[1..-2]? || ""
          else
            stripped
          end
        end
      end
    end

    class Jsonify
      extend Liquid::Filters::Filter

      def self.filter(data : Liquid::Any, args : Array(Liquid::Any), options : Hash(String, Liquid::Any)) : Liquid::Any
        json_string = JSON.build do |json|
          to_json_value(json, data.raw)
        end
        Liquid::Any.new(json_string)
      end

      private def self.to_json_value(json : JSON::Builder, value)
        case value
        when Hash
          json.object do
            value.each do |k, v|
              json.field(k.to_s) { to_json_value(json, v) }
            end
          end
        when Array
          json.array do
            value.each { |v| to_json_value(json, v) }
          end
        when Liquid::Any
          to_json_value(json, value.raw)
        when String
          json.string(value)
        when Int32, Int64
          json.number(value.to_i64)
        when Float32, Float64
          json.number(value.to_f64)
        when Bool
          json.bool(value)
        when Nil
          json.null
        else
          json.string(value.to_s)
        end
      end
    end

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

    class DateToXmlschema
      extend Liquid::Filters::Filter

      def self.filter(data : Liquid::Any, args : Array(Liquid::Any), options : Hash(String, Liquid::Any)) : Liquid::Any
        raw = data.raw
        time = case raw
               when Time
                 raw
               when String
                 begin
                   Time.parse_rfc3339(raw)
                 rescue
                   begin
                     Time.parse_iso8601(raw)
                   rescue
                     Time.parse(raw, "%Y-%m-%d", Time::Location.local)
                   end
                 end
               else
                 return Liquid::Any.new("")
               end
        Liquid::Any.new(time.to_s("%Y-%m-%dT%H:%M:%S%:z"))
      rescue
        Liquid::Any.new("")
      end
    end

    class Slugify
      extend Liquid::Filters::Filter

      def self.filter(data : Liquid::Any, args : Array(Liquid::Any), options : Hash(String, Liquid::Any)) : Liquid::Any
        return Liquid::Any.new("") if data.raw.nil?
        Liquid::Any.new(data.as_s.downcase.gsub(/([^\w_.]+)/, "-"))
      end
    end

    class RelativePath
      extend Liquid::Filters::Filter

      def self.filter(data : Liquid::Any, args : Array(Liquid::Any), options : Hash(String, Liquid::Any)) : Liquid::Any
        return Liquid::Any.new("") if data.raw.nil?
        Liquid::Any.new(data.as_s)
      end
    end

    class RelativeUrl
      extend Liquid::Filters::Filter

      def self.filter(data : Liquid::Any, args : Array(Liquid::Any), options : Hash(String, Liquid::Any)) : Liquid::Any
        return Liquid::Any.new("") if data.raw.nil?
        url = data.as_s || ""
        baseurl = LiquidFilters.baseurl
        if url.starts_with?("/")
          Liquid::Any.new(baseurl + url)
        else
          Liquid::Any.new(baseurl + "/" + url)
        end
      end
    end

    class AbsoluteUrl
      extend Liquid::Filters::Filter

      @@site_url : String = ""

      def self.site_url=(url : String)
        @@site_url = url
      end

      def self.filter(data : Liquid::Any, args : Array(Liquid::Any), options : Hash(String, Liquid::Any)) : Liquid::Any
        url = data.as_s || ""

        base_url = options["url"]?.try(&.as_s) || @@site_url
        base_url = base_url.rstrip('/')

        if url.starts_with?("http") || url.starts_with?("//")
          Liquid::Any.new(url)
        elsif url.starts_with?("/")
          Liquid::Any.new("#{base_url}#{url}")
        else
          Liquid::Any.new("#{base_url}/#{url}")
        end
      end
    end

    class Localize
      extend Liquid::Filters::Filter

      def self.filter(data : Liquid::Any, args : Array(Liquid::Any), options : Hash(String, Liquid::Any)) : Liquid::Any
        data
      end
    end

    class NormalizeWhitespace
      extend Liquid::Filters::Filter

      def self.filter(data : Liquid::Any, args : Array(Liquid::Any), options : Hash(String, Liquid::Any)) : Liquid::Any
        return Liquid::Any.new("") if data.raw.nil?
        Liquid::Any.new(data.as_s.gsub(/\s+/, ' '))
      end
    end

    class NewlineToBr
      extend Liquid::Filters::Filter

      def self.filter(data : Liquid::Any, args : Array(Liquid::Any), options : Hash(String, Liquid::Any)) : Liquid::Any
        return Liquid::Any.new("") if data.raw.nil?
        Liquid::Any.new(data.as_s.gsub(/\n/, "<br />\n"))
      end
    end

    class StripHtml
      extend Liquid::Filters::Filter

      def self.filter(data : Liquid::Any, args : Array(Liquid::Any), options : Hash(String, Liquid::Any)) : Liquid::Any
        return Liquid::Any.new("") if data.raw.nil?
        Liquid::Any.new(data.as_s.gsub(/<[^>]*>/, ""))
      end
    end

    class StripNewlines
      extend Liquid::Filters::Filter

      def self.filter(data : Liquid::Any, args : Array(Liquid::Any), options : Hash(String, Liquid::Any)) : Liquid::Any
        return Liquid::Any.new("") if data.raw.nil?
        Liquid::Any.new(data.as_s.gsub(/\n[\s]*/, ""))
      end
    end

    class Truncatewords
      extend Liquid::Filters::Filter

      def self.filter(data : Liquid::Any, args : Array(Liquid::Any), options : Hash(String, Liquid::Any)) : Liquid::Any
        return Liquid::Any.new("") if data.raw.nil?
        words = args[0]?.try(&.as_i) || 15
        Liquid::Any.new(data.as_s.split(/\s+/)[0, words].join(" "))
      end
    end

    class StripIndex
      extend Liquid::Filters::Filter

      def self.filter(data : Liquid::Any, args : Array(Liquid::Any), options : Hash(String, Liquid::Any)) : Liquid::Any
        return Liquid::Any.new("") if data.raw.nil?
        Liquid::Any.new(data.as_s.sub(%r{/?index\.html?$}, "/"))
      end
    end

    class Contains
      extend Liquid::Filters::Filter

      def self.filter(data : Liquid::Any, args : Array(Liquid::Any), options : Hash(String, Liquid::Any)) : Liquid::Any
        return Liquid::Any.new(false) if data.raw.nil?
        return Liquid::Any.new(false) if args.empty?
        search = args[0].as_s
        Liquid::Any.new(data.as_s.includes?(search))
      end
    end

    class Rstrip
      extend Liquid::Filters::Filter

      def self.filter(data : Liquid::Any, args : Array(Liquid::Any), options : Hash(String, Liquid::Any)) : Liquid::Any
        return Liquid::Any.new("") if data.raw.nil?
        Liquid::Any.new(data.as_s.rstrip)
      end
    end

    class Lstrip
      extend Liquid::Filters::Filter

      def self.filter(data : Liquid::Any, args : Array(Liquid::Any), options : Hash(String, Liquid::Any)) : Liquid::Any
        return Liquid::Any.new("") if data.raw.nil?
        Liquid::Any.new(data.as_s.lstrip)
      end
    end

    class Strip
      extend Liquid::Filters::Filter

      def self.filter(data : Liquid::Any, args : Array(Liquid::Any), options : Hash(String, Liquid::Any)) : Liquid::Any
        return Liquid::Any.new("") if data.raw.nil?
        Liquid::Any.new(data.as_s.strip)
      end
    end

    class Split
      extend Liquid::Filters::Filter

      def self.filter(data : Liquid::Any, args : Array(Liquid::Any), options : Hash(String, Liquid::Any)) : Liquid::Any
        return Liquid::Any.new([] of Liquid::Any) if data.raw.nil?
        pattern = args[0]?.try(&.as_s) || " "
        array = data.as_s.split(pattern).map { |string| Liquid::Any.new(string) }
        Liquid::Any.new(array)
      end
    end

    class Times
      extend Liquid::Filters::Filter

      def self.filter(data : Liquid::Any, args : Array(Liquid::Any), options : Hash(String, Liquid::Any)) : Liquid::Any
        return Liquid::Any.new("") if data.raw.nil?
        count = args[0]?.try(&.as_i) || 1
        return Liquid::Any.new("") if count <= 0
        Liquid::Any.new(data.as_s * count)
      end
    end

    class Slice
      extend Liquid::Filters::Filter

      def self.filter(data : Liquid::Any, args : Array(Liquid::Any), options : Hash(String, Liquid::Any)) : Liquid::Any
        return Liquid::Any.new("") if data.raw.nil?
        start_idx = args[0]?.try(&.as_i) || 0
        length = args[1]?.try(&.as_i) || 1
        str = data.as_s
        return Liquid::Any.new("") if start_idx < 0 || start_idx >= str.size
        Liquid::Any.new(str[start_idx, length])
      end
    end

    class Minus
      extend Liquid::Filters::Filter

      def self.filter(data : Liquid::Any, args : Array(Liquid::Any), options : Hash(String, Liquid::Any)) : Liquid::Any
        return Liquid::Any.new(0) if data.raw.nil?

        data_value = case raw = data.raw
                     when String
                       raw.to_i? || 0
                     when Int32, Int64
                       raw
                     else
                       data.as_i
                     end

        value = args[0]?.try(&.as_i) || 0
        Liquid::Any.new(data_value - value)
      end
    end

    class EscapeOnce
      extend Liquid::Filters::Filter

      def self.filter(data : Liquid::Any, args : Array(Liquid::Any), options : Hash(String, Liquid::Any)) : Liquid::Any
        return Liquid::Any.new("") if data.raw.nil?
        Liquid::Any.new(HTML.escape(data.as_s))
      end
    end

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

    class XmlEscape
      extend Liquid::Filters::Filter

      def self.filter(data : Liquid::Any, args : Array(Liquid::Any), options : Hash(String, Liquid::Any)) : Liquid::Any
        Liquid::Any.new(HTML.escape(data.as_s))
      end
    end
  end
end