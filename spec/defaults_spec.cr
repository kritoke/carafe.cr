require "spec"
require "../src/site"

describe Carafe::Site do
  describe "#defaults_for" do
    it "matches all" do
      config = Carafe::Config.new

      frontmatter = Carafe::Frontmatter{"match_all" => true}

      config.defaults = [Carafe::Config::Defaults.new(Carafe::Config::Scope.new, frontmatter)]

      site = Carafe::Site.new(config)

      site.defaults_for("foo.md", "post").should eq frontmatter
    end

    it "scope path" do
      config = Carafe::Config.new

      config.defaults = [
        Carafe::Config::Defaults.new(Carafe::Config::Scope.new, Carafe::Frontmatter{"match_all" => true}),
        Carafe::Config::Defaults.new(Carafe::Config::Scope.new(path: "*.md"), Carafe::Frontmatter{"path_md" => true}),
      ]

      site = Carafe::Site.new(config)

      site.defaults_for("foo.md", "post").should eq Carafe::Frontmatter{
        "match_all" => true,
        "path_md"   => true,
      }
    end

    it "scope type" do
      config = Carafe::Config.new

      config.defaults = [
        Carafe::Config::Defaults.new(Carafe::Config::Scope.new, Carafe::Frontmatter{"match_all" => true}),
        Carafe::Config::Defaults.new(Carafe::Config::Scope.new(type: "post"), Carafe::Frontmatter{"type_post" => true}),
      ]

      site = Carafe::Site.new(config)

      site.defaults_for("foo.md", "post").should eq Carafe::Frontmatter{
        "match_all" => true,
        "type_post" => true,
      }
    end

    it "scope type" do
      config = Carafe::Config.new

      config.defaults = [
        Carafe::Config::Defaults.new(Carafe::Config::Scope.new, Carafe::Frontmatter{"match_all" => true}),
        Carafe::Config::Defaults.new(Carafe::Config::Scope.new(type: "post"), Carafe::Frontmatter{"type_post" => true}),
        Carafe::Config::Defaults.new(Carafe::Config::Scope.new(path: "*.md"), Carafe::Frontmatter{"path_md" => true}),
        Carafe::Config::Defaults.new(Carafe::Config::Scope.new(type: "page"), Carafe::Frontmatter{"type_page" => true}),
        Carafe::Config::Defaults.new(Carafe::Config::Scope.new(path: "*.html"), Carafe::Frontmatter{"path_html" => true}),
      ]

      site = Carafe::Site.new(config)

      site.defaults_for("foo.md", "post").should eq Carafe::Frontmatter{
        "match_all" => true,
        "type_post" => true,
        "path_md"   => true,
      }
    end

    it "scope override" do
      config = Carafe::Config.new

      config.defaults = [
        Carafe::Config::Defaults.new(Carafe::Config::Scope.new, Carafe::Frontmatter{"foo" => "bar"}),
        Carafe::Config::Defaults.new(Carafe::Config::Scope.new, Carafe::Frontmatter{"foo" => "baz"}),
      ]

      site = Carafe::Site.new(config)

      site.defaults_for("foo.md", "post").should eq Carafe::Frontmatter{
        "foo" => "baz",
      }
    end
  end
end
