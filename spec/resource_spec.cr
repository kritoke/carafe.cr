require "spec"
require "../src/resource"

def test_resource(slug, frontmatter = nil, site = Carafe::Site.new, output_ext = nil)
  resource = Carafe::Resource.new(site, slug, frontmatter: frontmatter)
  if output_ext
    resource.output_ext = output_ext
  end
  resource
end

describe Carafe::Resource do
  describe ".new" do
    it do
      resource = Carafe::Resource.new(nil, "foo/bar.html")

      resource.slug.should eq "foo/bar.html"

      resource.name.should eq "bar.html"
      resource.basename.should eq "bar"
      resource.extname.should eq ".html"
      resource.has_frontmatter?.should be_true
    end
  end

  describe "#url" do
    it do
      test_resource("foo/bar.html").url.to_s.should eq "/foo/bar"
    end
  end

  describe ".url_for" do
    it do
      Carafe::Resource.url_for(test_resource("foo.md", output_ext: ".html")).to_s.should eq "/foo"
      Carafe::Resource.url_for(test_resource("foo/bar.html")).to_s.should eq "/foo/bar"
    end
  end

  describe "#permalink" do
    it do
      test_resource("foo/bar.html").permalink.should eq "/foo/bar.html"
      test_resource("foo/bar.html", frontmatter: Carafe::Frontmatter{"permalink" => "baz.html"}).permalink.should eq "/baz.html"
    end
  end

  describe "#output_path" do
    it do
      test_resource("foo/bar.html").output_path.should eq "/foo/bar.html"
      test_resource("foo/bar.html", frontmatter: Carafe::Frontmatter{"domain" => "baz.com"}).output_path.should eq "/baz.com/foo/bar.html"
    end
  end

  it "#has_frontmatter" do
    site = Carafe::Site.new
    resource = Carafe::Resource.new(site, "foo/bar.html", frontmatter: nil)

    resource.has_frontmatter?.should be_false
  end

  it "#expand_permalink" do
    test_resource("2018-10-23-test.md", frontmatter: Carafe::Frontmatter{"categories" => "foo bar"}).expand_permalink("pretty").should eq "/foo/bar/2018/10/23/test/"
  end

  describe "#[]" do
    it "raises" do
      site = Carafe::Site.new
      resource = Carafe::Resource.new(site, "foo.md")

      expect_raises(KeyError, %(Missing resource frontmatter key: "foo")) do
        resource["foo"]
      end
    end

    it "falls back to defaults" do
      site = Carafe::Site.new

      defaults = Carafe::Frontmatter{
        "foo" => "bar",
        "baz" => "not-baz",
      }

      resource = Carafe::Resource.new(site, "foo.md", frontmatter: Carafe::Frontmatter{"baz" => "baz"}, defaults: defaults)
      resource["foo"].should eq "bar"
      resource["baz"].should eq "baz"
    end
  end
end
