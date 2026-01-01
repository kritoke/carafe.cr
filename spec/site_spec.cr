require "spec"
require "../src/site"

describe Carafe::Site do
  it ".new" do
    config = Carafe::Config.new
    site = Carafe::Site.new(config)
    site.config.should eq config
  end

  it "#collections" do
    config = Carafe::Config.new
    site = Carafe::Site.new(config)
    site.collections.keys.should eq ["posts"]
    site.collections["posts"].defaults.should eq config.collections["posts"]
  end

  it "#site_dir" do
    site = Carafe::Site.new("spec/fixtures/simple-site")
    site.site_dir.should eq File.join(Dir.current, "spec/fixtures/simple-site")
  end

  it "#run_generators" do
    site = Carafe::Site.new("spec/fixtures/simple-site")

    site.run_generators

    site.files.size.should_not eq 0
    site.collections.size.should_not eq 0

    site.collections["posts"]?.should_not be_nil
    site.collections["posts"].resources.size.should_not eq 0
  end

  it "#run_processor" do
    site = Carafe::Site.new
    resource = Carafe::Resource.new(site, "sample.md", "Foo **{{ page.name }}**")
    string = String.build do |io|
      site.run_processor(io, resource)
    end

    string.should eq "<p>Foo <strong>sample.md</strong></p>\n"
  end
end
