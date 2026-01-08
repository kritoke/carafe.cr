require "liquid"

# Jekyll-compatible Liquid filters for Carafe
module Liquid::Filters
  # Class variable to store site URL for absolute_url filter
  @@site_url : String = ""

  def self.site_url=(url : String)
    @@site_url = url
  end

  # jsonify filter - convert objects to JSON for JSON-LD schema
  class Jsonify
    extend Filter

    def self.filter(data : Any, args : Array(Any), options : Hash(String, Any)) : Any
      raw = data.raw

      # Convert to JSON string using JSON.build
      json_string = JSON.build do |json|
        to_json_value(json, raw)
      end

      Any.new(json_string)
    end

    private def self.to_json_value(json : JSON::Builder, value)
      case value
      when Hash
        json.object do
          value.each do |k, v|
            json.field(k.to_s) do
              to_json_value(json, v)
            end
          end
        end
      when Array
        json.array do
          value.each do |v|
            to_json_value(json, v)
          end
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

  FilterRegister.register "jsonify", Jsonify

  # absolute_url filter - prepend site URL to paths
  class AbsoluteUrl
    extend Filter

    @@site_url : String = ""

    def self.site_url=(url : String)
      @@site_url = url
    end

    def self.filter(data : Any, args : Array(Any), options : Hash(String, Any)) : Any
      url = data.as_s || ""

      # Try to get base_url from options first, then from class variable
      base_url = options["url"]?.try(&.as_s) || @@site_url

      # Remove trailing slash from base_url
      base_url = base_url.rstrip('/')

      # If already absolute, return as-is
      if url.starts_with?("http") || url.starts_with?("//")
        Any.new(url)
      elsif url.starts_with?("/")
        Any.new("#{base_url}#{url}")
      else
        Any.new("#{base_url}/#{url}")
      end
    end
  end

  FilterRegister.register "absolute_url", AbsoluteUrl

  # date_to_xmlschema filter - convert dates to XML schema format
  class DateToXmlschema
    extend Filter

    def self.filter(data : Any, args : Array(Any), options : Hash(String, Any)) : Any
      raw = data.raw
      time = case raw
             when Time
               raw
             when String
               Time.parse_iso8601(raw)
             else
               return Any.new("")
             end

      Any.new(time.to_s("%Y-%m-%dT%H:%M:%S%:z"))
    rescue
      Any.new("")
    end
  end

  FilterRegister.register "date_to_xmlschema", DateToXmlschema

  # escape_once filter - HTML escape but only once
  class EscapeOnce
    extend Filter

    def self.filter(data : Any, args : Array(Any), options : Hash(String, Any)) : Any
      str = data.as_s || ""
      # Only escape & if not already escaped
      unless str.includes?("&amp;")
        str = str.gsub("&", "&amp;")
      end
      str = str.gsub("<", "&lt;").gsub(">", "&gt;").gsub("\"", "&quot;")
      Any.new(str)
    end
  end

  FilterRegister.register "escape_once", EscapeOnce

  # strip_html filter - remove HTML tags
  class StripHtml
    extend Filter

    def self.filter(data : Any, args : Array(Any), options : Hash(String, Any)) : Any
      str = data.as_s || ""
      Any.new(str.gsub(/<[^>]+>/, ""))
    end
  end

  FilterRegister.register "strip_html", StripHtml

  # newline_to_br filter - convert newlines to <br /> tags
  class NewlineToBr
    extend Filter

    def self.filter(data : Any, args : Array(Any), options : Hash(String, Any)) : Any
      str = data.as_s || ""
      Any.new(str.gsub("\n", "<br />"))
    end
  end

  FilterRegister.register "newline_to_br", NewlineToBr

  # markdownify filter - convert markdown to HTML (already processed, so just return as-is)
  class Markdownify
    extend Filter

    def self.filter(data : Any, args : Array(Any), options : Hash(String, Any)) : Any
      data
    end
  end

  FilterRegister.register "markdownify", Markdownify
end
