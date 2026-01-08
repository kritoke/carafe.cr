require "../spec_helper"

describe Carafe::Plugins::Lunr do
  describe "#enabled?" do
    it "returns false when search is not set" do
      config = Carafe::Config.new
      plugin = Carafe::Plugins::Lunr.new
      plugin.enabled?(config).should be_false
    end

    it "returns true when search is set to true" do
      config = Carafe::Config.new
      config["search"] = YAML::Any.new(true)
      plugin = Carafe::Plugins::Lunr.new
      plugin.enabled?(config).should be_true
    end

    it "returns true when search is set to a hash" do
      config = Carafe::Config.new
      hash = Hash(YAML::Any, YAML::Any).new
      hash[YAML::Any.new("index")] = YAML::Any.new("search.json")
      config["search"] = YAML::Any.new(hash)
      plugin = Carafe::Plugins::Lunr.new
      plugin.enabled?(config).should be_true
    end
  end

  describe "#register" do
    it "adds Lunr generator to site" do
      config = Carafe::Config.new
      site = Carafe::Site.new(config)
      plugin = Carafe::Plugins::Lunr.new

      plugin.register(site)

      site.generators.size.should be > 0
      site.generators.find { |generator| generator.is_a?(Carafe::Plugins::Lunr::Generator) }.should_not be_nil
    end
  end
end

describe Carafe::Plugins::Lunr::Generator do
  it "has LOW priority" do
    site = Carafe::Site.new
    generator = Carafe::Plugins::Lunr::Generator.new(site)
    generator.priority.should eq Carafe::Priority::LOW
  end

  pending "generates search index from files"
  pending "excludes CSS and JS files from search index"
  pending "extracts plain text from HTML content"
end
