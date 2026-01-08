require "../spec_helper"

describe Carafe::Plugins::Pagination do
  describe "#enabled?" do
    it "returns false when paginate is not set" do
      config = Carafe::Config.new
      plugin = Carafe::Plugins::Pagination.new
      plugin.enabled?(config).should be_false
    end

    it "returns true when paginate is set to a number" do
      config = Carafe::Config.new
      config["paginate"] = YAML::Any.new(5)
      plugin = Carafe::Plugins::Pagination.new
      plugin.enabled?(config).should be_true
    end

    it "returns true when paginate is set to true" do
      config = Carafe::Config.new
      config["paginate"] = YAML::Any.new(true)
      plugin = Carafe::Plugins::Pagination.new
      plugin.enabled?(config).should be_true
    end
  end

  describe "#register" do
    it "adds the pagination generator to the site" do
      config = Carafe::Config.new
      site = Carafe::Site.new(config)
      plugin = Carafe::Plugins::Pagination.new

      plugin.register(site)

      site.generators.size.should be > 0
      site.generators.find { |generator| generator.is_a?(Carafe::Plugins::Pagination::Generator) }.should_not be_nil
    end
  end
end

describe Carafe::Plugins::Pagination::Generator do
  it "adds paginator to resource" do
    site = Carafe::Site.new
    site.posts << Carafe::Resource.new(site, "baz.md")
    site.posts << Carafe::Resource.new(site, "bar.md")

    index = Carafe::Resource.new(site, "index.html", frontmatter: Carafe::Frontmatter{
      "paginate" => Hash(YAML::Any, YAML::Any){
        YAML::Any.new("collection") => YAML::Any.new("posts"),
      },
    })
    site.files << index

    generator = Carafe::Plugins::Pagination::Generator.new(site)
    generator.generate

    index.paginator.should_not be_nil
    index.paginator.as(Carafe::Paginator).items.map(&.slug).should eq ["baz.md", "bar.md"]
  end

  it "sorts items when sort is enabled" do
    site = Carafe::Site.new
    site.posts << Carafe::Resource.new(site, "baz.md")
    site.posts << Carafe::Resource.new(site, "bar.md")

    index = Carafe::Resource.new(site, "index.html", frontmatter: Carafe::Frontmatter{
      "paginate" => Hash(YAML::Any, YAML::Any){
        YAML::Any.new("collection") => YAML::Any.new("posts"),
        YAML::Any.new("sort")       => YAML::Any.new(true),
      },
    })
    site.files << index

    generator = Carafe::Plugins::Pagination::Generator.new(site)
    generator.generate

    index.paginator.as(Carafe::Paginator).items.map(&.slug).should eq ["bar.md", "baz.md"]
  end

  it "creates multiple pages when per_page is set" do
    site = Carafe::Site.new
    site.posts << Carafe::Resource.new(site, "baz.md")
    site.posts << Carafe::Resource.new(site, "bar.md")
    site.posts << Carafe::Resource.new(site, "qux.md")

    index = Carafe::Resource.new(site, "index.html", frontmatter: Carafe::Frontmatter{
      "paginate" => Hash(YAML::Any, YAML::Any){
        YAML::Any.new("collection") => YAML::Any.new("posts"),
        YAML::Any.new("per_page")   => YAML::Any.new(2_i64),
      },
    })
    site.files << index

    generator = Carafe::Plugins::Pagination::Generator.new(site)
    generator.generate

    # First page should have 2 items
    index.paginator.as(Carafe::Paginator).items.size.should eq 2
    # Should have added a second page resource
    site.files.size.should eq 2
  end

  it "has LOW priority" do
    site = Carafe::Site.new
    generator = Carafe::Plugins::Pagination::Generator.new(site)
    generator.priority.should eq Carafe::Priority::LOW
  end
end
