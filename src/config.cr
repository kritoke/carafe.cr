require "yaml"
require "./frontmatter"
require "./util/yaml_unmapped"
require "./util/def_and_equals"

class Carafe::Config
  class Collection
    include YAML::Serializable
    include YAML::Serializable::Unmapped
    include Util::YAMLUnmapped

    property? output : Bool = true

    def initialize
    end

    include Util::DefAndEquals
  end

  class Defaults
    include YAML::Serializable

    property scope : Scope = Carafe::Config::Scope.new

    property values : Carafe::Frontmatter = Carafe::Frontmatter.new

    def initialize(@scope : Scope = Scope.new, @values : Carafe::Frontmatter = Carafe::Frontmatter.new)
    end

    include Util::DefAndEquals
  end

  struct Scope
    include YAML::Serializable

    getter path : String? = nil

    getter type : String? = nil

    def initialize(@path : String? = nil, @type : String? = nil)
    end

    include Util::DefAndEquals
  end

  def initialize(@site_dir : String = ".")
    merge_defaults
  end

  include YAML::Serializable
  include YAML::Serializable::Unmapped
  include Util::YAMLUnmapped

  property site_dir : String = "."
  property source : String = "."
  property destination : String = "_site"
  property collections_dir : String = "."

  # property plugins_dir : String = "_plugins"
  property layouts_dir : String = "_layouts"
  property data_dir : String = "_data"
  property includes_dir : String = "_includes"

  # TODO: Add support for Array(String)
  property collections : Hash(String, ::Carafe::Config::Collection) = {} of String => ::Carafe::Config::Collection

  # Handling Reading
  # property? safe : Bool = false
  property include : Array(String) = [".htaccess"]
  property exclude : Array(String) = %w[
    Gemfile Gemfile.lock node_modules vendor/bundle/ vendor/cache/ vendor/gems/
    vendor/ruby/ *.nix gemset.nix
  ]
  property keep_files : Array(String) = [".git", ".svn"]
  property encoding : String = "utf-8"
  property markdown_ext : String = "markdown,mkdown,mkdn,mkd,md"
  # property? strict_front_matter : Bool = false

  # Filtering Content
  # property show_drafts : Nil = nil
  # property limit_posts : Int32 = 0
  property? future : Bool = false
  property? unpublished : Bool = false

  # Plugins
  # property whitelist : Array(String) = [] of String
  # property plugins : Array(String) = [] of String

  # Conversion
  # property markdown : String = "kramdown"
  # property highlighter : String = "rouge"
  # property lsi : Bool = false
  property excerpt_separator : String = "\n\n"
  # property icremental : Bool = false

  # Serving
  property? detach : Bool = false # default to not detaching the server
  property port : Int32 = 4000
  property host : String = "127.0.0.1"
  property baseurl : String = ""
  property? show_dir_listing : Bool = true

  property? livereload : Bool = true
  property livereload_port : Int32 = 35729

  # Output Configuration
  property permalink : String = "date"
  property paginate_path : String = "/page:num"
  property timezone : String? = nil # use the local timezone

  property sass_bin : String? = nil
  property? quiet : Bool = false
  property? verbose : Bool = false
  property defaults : Array(Carafe::Config::Defaults) = [] of Carafe::Config::Defaults

  include Util::DefAndEquals

  # property liquid
  #   property error_mode : String = "warn"
  #   property strict_filters : Bool = false
  #   property strict_variables : Bool = false
  # },

  # "kramdown"            => {
  #   property auto_ids : Bool = true
  #   property toc_levels : String = "1..6"
  #   property entity_output : String = "as_char"
  #   property smart_quotes : String = "lsquo,rsquo,ldquo,rdquo"
  #   property input : Bool = "GFM"
  #   property hard_wrap : Bool = false
  #   property footnote_nr : String = 1
  #   property show_warnings : Bool = false

  def merge_defaults
    posts = collections["posts"] ||= Config::Collection.new
    posts["permalink"] ||= permalink
    # Don't hardcode the layout - let Jekyll's defaults system handle it
    # posts["layout"] ||= "post"

    # Jekyll automatically treats _pages as a collection
    pages = collections["pages"] ||= Config::Collection.new
    pages["output"] ||= true
  end

  def self.load_file(filename : String) : Config
    File.open(filename, "r") do |io|
      from_yaml(io).tap do |config|
        config.merge_defaults
      end
    end
  end

  def self.load(site_dir : String, alternatives : Enumerable = {"_config.yml", ".Carafe/config.yml"})
    alternatives.each do |filename|
      full_path = File.join(site_dir, filename)
      if File.exists?(full_path)
        return load_file(full_path).tap do |config|
          config.site_dir = site_dir
        end
      end
    end

    raise "Could not find Carafe config file in #{site_dir} (looking for #{alternatives.join(", ")})"
  end
end
