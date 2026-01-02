require "spec"
require "../../src/processor/layout"

describe Carafe::Processor::Layout do
  it "renders layouts" do
    site = Carafe::Site.new
    processor = Carafe::Processor::Layout.new
    processor.layouts["page"] = {
      Crinja::Template.new("<page>{{ content }}</page>"),
      Carafe::Frontmatter{"layout" => "base"},
    }
    processor.layouts["base"] = {
      Crinja::Template.new("<base>{{ content }}</base>"),
      Carafe::Frontmatter.new,
    }
    resource = Carafe::Resource.new(site, "foo.md", frontmatter: Carafe::Frontmatter{"layout" => "page"})

    processor.process(resource, "Laus deo semper").should eq "<base><page>Laus deo semper</page></base>\n"
  end

  it "none layout" do
    site = Carafe::Site.new
    processor = Carafe::Processor::Layout.new

    processor.process(Carafe::Resource.new(site, "foo.md", frontmatter: Carafe::Frontmatter{"layout" => "none"}), "Laus deo semper").should be_nil

    processor.process(Carafe::Resource.new(site, "foo.md"), "Laus deo semper").should be_nil
  end

  it "template loader" do
    site = Carafe::Site.new
    processor = Carafe::Processor::Layout.new(layouts_path: "spec/fixtures/simple-site/_layouts")
    resource = Carafe::Resource.new(site, "foo.md", frontmatter: Carafe::Frontmatter{"layout" => "simple"})

    processor.process(resource, "Laus deo semper").should eq <<-HTML
      <html>
        <body>
          Laus deo semper
        </body>
      </html>

      HTML
  end

  it "loads from includes dir" do
    site = Carafe::Site.new
    resource = Carafe::Resource.new(site, "foo.md", frontmatter: Carafe::Frontmatter{"layout" => "include"})
    processor = Carafe::Processor::Layout.new(layouts_path: "spec/fixtures/simple-site/_layouts", includes_path: "spec/fixtures/simple-site/_includes")

    processor.process(resource, "content").should eq "FOO included\n\ncontent\n"
  end
end
