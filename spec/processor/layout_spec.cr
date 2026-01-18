require "spec"
require "../../src/processor/layout"

describe Carafe::Processor::Layout do
  it "renders layouts" do
    site = Carafe::Site.new
    processor = Carafe::Processor::Layout.new(site)
    processor.layouts["page"] = {
      "<page>{{ content }}</page>",
      Carafe::Frontmatter{"layout" => "base"},
    }
    processor.layouts["base"] = {
      "<base>{{ content }}</base>",
      Carafe::Frontmatter.new,
    }
    resource = Carafe::Resource.new(site, "foo.md", frontmatter: Carafe::Frontmatter{"layout" => "page"})

    io = IO::Memory.new
    processor.process(resource, IO::Memory.new("Laus deo semper"), io).should be_true
    io.to_s.should eq "<base><page>Laus deo semper</page></base>\n"
  end

  it "none layout" do
    site = Carafe::Site.new
    processor = Carafe::Processor::Layout.new(site)

    io = IO::Memory.new
    processor.process(Carafe::Resource.new(site, "foo.md", frontmatter: Carafe::Frontmatter{"layout" => "none"}), IO::Memory.new("Laus deo semper"), io).should be_false

    io = IO::Memory.new
    processor.process(Carafe::Resource.new(site, "foo.md"), IO::Memory.new("Laus deo semper"), io).should be_false
  end

  it "template loader" do
    site = Carafe::Site.new
    processor = Carafe::Processor::Layout.new(site, layouts_path: "spec/fixtures/simple-site/_layouts")
    resource = Carafe::Resource.new(site, "foo.md", frontmatter: Carafe::Frontmatter{"layout" => "simple"})

    io = IO::Memory.new
    processor.process(resource, IO::Memory.new("Laus deo semper"), io).should be_true
    io.to_s.should eq "<html>\n  <body>\n    Laus deo semper\n  </body>\n</html>\n"
  end

  it "loads from includes dir" do
    site = Carafe::Site.new
    resource = Carafe::Resource.new(site, "foo.md", frontmatter: Carafe::Frontmatter{"layout" => "include"})
    processor = Carafe::Processor::Layout.new(site, layouts_path: "spec/fixtures/simple-site/_layouts", includes_path: "spec/fixtures/simple-site/_includes")

    io = IO::Memory.new
    processor.process(resource, IO::Memory.new("content"), io).should be_true
    io.to_s.should eq "FOO included\n\ncontent\n"
  end
end
