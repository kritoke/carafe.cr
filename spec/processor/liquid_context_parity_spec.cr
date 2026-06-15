require "spec"
require "../../src/site"
require "../../src/processor/liquid"
require "../../src/processor/layout"

# Parity spec: the SAME `site.*` expression MUST render identically whether it
# appears in page content (Processor::Liquid) or in a layout (Processor::Layout).
#
# This is the core divergence the unify-liquid-context-builder OpenSpec fixes.
# Today these fail because the two processors build structurally different
# `site` objects (collections as array vs hash; site.posts/data/config absent
# in page context).

describe "Liquid context render parity" do
  setup_site = -> do
    site = Carafe::Site.new
    site.collections["posts"] = Carafe::Collection.new("posts")
    site.collections["posts"].resources << Carafe::Resource.new(site, "2024-03-01-newer.md",
      frontmatter: Carafe::Frontmatter{"title" => "Newer"})
    site.collections["posts"].resources << Carafe::Resource.new(site, "2024-01-01-older.md",
      frontmatter: Carafe::Frontmatter{"title" => "Older"})
    site.collections["tutorials"] = Carafe::Collection.new("tutorials")
    site.collections["tutorials"].resources << Carafe::Resource.new(site, "intro.md",
      frontmatter: Carafe::Frontmatter{"title" => "Intro"})
    site.data["nav"] = YAML.parse(%({"items": ["a", "b"]}))
    site
  end

  describe "site.collections.posts.docs.size" do
    it "renders the same value via Liquid and Layout processors" do
      site = setup_site.call
      assert_parity(site, "{{ site.collections.posts.docs.size }}", "2")
    end
  end

  describe "site.collections.tutorials.docs.size" do
    it "renders the same value via Liquid and Layout processors" do
      site = setup_site.call
      assert_parity(site, "{{ site.collections.tutorials.docs.size }}", "1")
    end
  end

  describe "site.posts.size" do
    it "renders the same value via Liquid and Layout processors" do
      site = setup_site.call
      assert_parity(site, "{{ site.posts.size }}", "2")
    end
  end

  describe "site.data.nav.items.size" do
    it "renders the same value via Liquid and Layout processors" do
      site = setup_site.call
      assert_parity(site, "{{ site.data.nav.items.size }}", "2")
    end
  end

  describe "site.config.source" do
    it "renders the same value via Liquid and Layout processors" do
      site = setup_site.call
      assert_parity(site, "{{ site.config.source }}", site.config.source)
    end
  end
end

# Renders `expr` via Processor::Liquid (page content) and Processor::Layout,
# asserts both equal `expected`. This is the parity guarantee: one shape,
# both paths.
private def assert_parity(site : Carafe::Site, expr : String, expected : String) : Nil
  via_liquid = render_via_liquid_processor(site, expr)
  via_layout = render_via_layout_processor(site, expr)

  via_liquid.should eq(expected), "via Processor::Liquid: expected #{expected.inspect}, got #{via_liquid.inspect}"
  via_layout.should eq(expected), "via Processor::Layout: expected #{expected.inspect}, got #{via_layout.inspect}"
end

private def render_via_liquid_processor(site : Carafe::Site, expr : String) : String
  resource = Carafe::Resource.new(site, "page.md")
  processor = Carafe::Processor::Liquid.new(site)
  io = IO::Memory.new
  processor.process(resource, IO::Memory.new(expr), io)
  io.to_s.strip
end

private def render_via_layout_processor(site : Carafe::Site, expr : String) : String
  resource = Carafe::Resource.new(site, "page.md",
    frontmatter: Carafe::Frontmatter{"layout" => "parity"})
  processor = Carafe::Processor::Layout.new(site)
  processor.layouts["parity"] = {expr, Carafe::Frontmatter.new}
  io = IO::Memory.new
  processor.process(resource, IO::Memory.new("body"), io)
  io.to_s.strip
end
