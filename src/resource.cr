require "./site"
require "uri"
require "crinja"
require "./generator"
require "./frontmatter"
require "./paginator"
require "./ext/string"

@[::Crinja::Attributes(expose: [:slug, :directory, :content, :paginator, :categories, :title, :date, :permalink, :url])]
class Carafe::Resource
  include ::Crinja::Object::Auto
  include Comparable(Resource)

  getter slug : String
  getter directory : String?
  getter content : String?
  getter frontmatter : Frontmatter
  getter defaults : Frontmatter
  getter? has_frontmatter : Bool
  property updated_at : Time? = nil
  property? created_at : Time? = nil
  property collection : Collection? = nil
  property paginator : Paginator? = nil
  property output_ext : String? = nil
  property url : URI? = nil

  def initialize(site : Site?, @slug : String, @content : String? = nil, @directory : String? = nil,
                 frontmatter : Frontmatter? = Frontmatter.new, @defaults : Frontmatter = Frontmatter.new)
    @has_frontmatter = !frontmatter.nil?
    @frontmatter = frontmatter || Frontmatter.new

    site.try &.register(self)
  end

  def [](key : String) : YAML::Any
    @frontmatter.fetch(key) do
      defaults[key]? || @collection.try(&.defaults[key]?) || raise KeyError.new "Missing resource frontmatter key: #{key.inspect}"
    end
  end

  def []?(key : String) : YAML::Any?
    @frontmatter.fetch(key) do
      defaults[key]? || @collection.try(&.defaults[key]?)
    end
  end

  def has_key?(key : String) : Bool
    @frontmatter.has_key?(key) || defaults.has_key?(key) || @collection.try(&.defaults.has_key?(key)) || false
  end

  @[Crinja::Attribute]
  def title : String?
    self["title"]?.try &.to_s
  end

  @[Crinja::Attribute]
  def name : String
    File.basename(@slug)
  end

  @[Crinja::Attribute]
  def basename : String
    File.basename(@slug, File.extname(@slug))
  end

  @[Crinja::Attribute]
  def extname : String
    File.extname(@slug)
  end

  @[Crinja::Attribute]
  getter date : Time do
    if date = self["date"]?
      case raw = date.raw
      when Time
        raw
      when String
        Time.parse(raw, "%Y-%m-%d %H:%M", Time::Location.local)
      else
        raise "Unknown date format (#{raw})"
      end
    elsif date = date_and_shortname_from_slug.first
      date
      # elsif @slug && File.exists?(@slug)
      #   File.mtime(@slug)
    else
      Time.local.at_beginning_of_day
    end
  end

  def self.url_for(resource : Resource) : URI
    permalink = resource["permalink"]?
    if permalink
      path = resource.expand_permalink(permalink.as_s)
    else
      path = String.build do |io|
        io << '/'
        dirname = File.dirname(resource.slug)
        if dirname != "."
          io << dirname
          io << '/'
        end

        basename = resource.basename
        if basename != "index"
          io << basename
          output_ext = resource.output_ext
          if output_ext != ".html"
            io << resource.output_ext
          end
        end
      end
    end

    # base = @site.url
    # scheme = self["scheme"]
    # domain = self["domain"]

    URI.parse(path)
  end

  @[Crinja::Attribute]
  def permalink : String
    if permalink = self["permalink"]?
      permalink = permalink.as_s
      unless permalink.starts_with?('/')
        permalink = "/#{permalink}"
      end
      return permalink
    end

    dir = File.expand_path(File.dirname(@slug), "/")

    File.expand_path("#{basename}#{output_ext}", dir)
  end

  def crinja_attribute(value : Crinja::Value) : Crinja::Value
    case value.to_string
    when "url"
      return Crinja::Value.new(url.try(&.to_s) || "")
    when "date"
      return Crinja::Value.new(date)
    end

    result = super

    if result.undefined?
      key = value.to_string
      if val = self[key]?
        return Config.yaml_to_crinja(val)
      end
    end

    result
  end

  getter categories : Array(String) do
    if (categories = self["categories"]?) && (categories = categories.raw)
      if categories.is_a?(Array)
        return categories.map(&.to_s).reject(&.empty?)
      elsif categories.is_a?(String)
        return categories.split(' ', remove_empty: true)
      end
    end
    if (category = self["category"]?) && (category = category.raw)
      if category.is_a?(String) && !category.empty?
        return [category]
      end
    end

    return [] of String
  end

  def output_path : String
    output_path = expand_permalink(permalink)

    if output_path.ends_with?('/')
      output_path = "#{output_path}index#{output_ext || ".html"}"
    elsif File.extname(output_path).empty? && has_key?("permalink") && (output_ext = self.output_ext)
      output_path += output_ext
    end

    if domain = self["domain"]?
      output_path = File.join("/", domain.to_s, output_path)
    end

    output_path
  end

  def <=>(other : Resource)
    ret = other.date <=> date
    return ret unless ret == 0

    slug <=> other.slug
  end

  def to_s(io)
    # io << self.class << "(" << @slug << ", " << content_type << ")"
    io << @slug
  end

  def date_and_shortname_from_slug : {Time?, String?}
    basename = self.basename

    if basename && (data = basename.match /^(?:(\d{2}\d{2}?)-(\d{1,2})-(\d{1,2})-)?(.+)$/)
      if data[1]?
        date = Time.local(data[1].to_i, data[2].to_i, data[3].to_i)
      end
      name = data[4]
    end

    {date, name}
  end

  def expand_permalink(permalink : String)
    permalink = case permalink.lchop('/')
                when "date"    then "/:categories/:year/:month/:day/:title:output_ext"
                when "pretty"  then "/:categories/:year/:month/:day/:title/"
                when "ordinal" then "/:categories/:year/:y_day/:title:output_ext"
                when "none"    then "/:categories/:title:output_ext"
                else                permalink
                end

    date, shortname = date_and_shortname_from_slug
    date ||= self.date

    tokens = {
      "year"        => date.to_s("%Y"),
      "month"       => date.to_s("%m"),
      "day"         => date.to_s("%d"),
      "hour"        => date.to_s("%H"),
      "minute"      => date.to_s("%M"),
      "second"      => date.to_s("%S"),
      "i_day"       => date.to_s("%-d"),
      "i_month"     => date.to_s("%-m"),
      "short_month" => date.to_s("%b"),
      "short_year"  => date.to_s("%y"),
      "y_day"       => date.to_s("%j"),
      "title"       => shortname.to_s,
      "slug"        => shortname.to_s.downcase,
      "name"        => name.to_s,
      "basename"    => basename.to_s,
      "collection"  => collection.try(&.name).to_s,
      "output_ext"  => output_ext.to_s,
      "categories"  => categories.map(&.slugify).join("/"),
      "path"        => (path_dir = File.dirname(@slug); path_dir == "." ? "" : path_dir),
    }

    permalink.gsub(/\{:(\w+)\}|:(\w+)/) do |_, match|
      variable = match[1]? || match[2]
      tokens.fetch(variable) { raise "Unknown permalink variable #{variable.dump}" }
    end.gsub(%r{/\.?/+}, '/')
  end
end
