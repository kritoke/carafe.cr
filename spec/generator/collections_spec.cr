require "spec"
require "../../src/generator"

describe Carafe::Generator::Collections do
  it "reads files" do
    site = Carafe::Site.new("spec/fixtures/simple-site")
    generator = Carafe::Generator::Collections.new(site, ["_posts"])
    generator.generate

    resource = site.collections["posts"].resources.sort_by(&.slug).first
    resource.slug.should eq "2017-07-16-my-first-post.html"
    # resource.output_path("/").should eq "/2017-07-16-my-first-post.html"
    resource.output_path.should eq "/2017/07/16/my-first-post.html"
    resource.directory.should eq "_posts"
    resource.content.should eq "\n<p>Hello World!</p>\n"
    resource.title.should eq "My first post"
    resource["author"].should eq "straight-shoota"
  end

  it "applies defaults" do
    config = Carafe::Config.new
    config.site_dir = "spec/fixtures/simple-site"
    config.defaults = [Carafe::Config::Defaults.new(Carafe::Config::Scope.new(type: "posts"), Carafe::Frontmatter{"defaults_applied" => true})]

    site = Carafe::Site.new(config)
    generator = Carafe::Generator::Collections.new(site, ["_posts"])
    generator.generate

    site.collections["posts"].resources.sort_by(&.slug).first["defaults_applied"].should be_true
  end
end
