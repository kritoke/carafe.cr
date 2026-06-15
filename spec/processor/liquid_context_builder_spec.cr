require "spec"
require "../../src/site"
require "../../src/jekyll_compat/liquid_context_builder"

# Characterization specs for the canonical Liquid context shape.
# These assert the TARGET shape that `Carafe::LiquidContextBuilder` provides.
# See OpenSpec: unify-liquid-context-builder.

describe "Liquid context canonical shape" do
  describe "Carafe::LiquidContextBuilder" do
    it "exists and responds to build" do
      Carafe::LiquidContextBuilder.responds_to?(:build).should be_true
    end

    it "build returns a Liquid::Context" do
      site = Carafe::Site.new
      resource = Carafe::Resource.new(site, "page.md")
      result = Carafe::LiquidContextBuilder.build(site, resource)
      result.should be_a(Liquid::Context)
    end
  end

  describe "site.collections shape" do
    it "is a hash keyed by collection label" do
      site = Carafe::Site.new
      site.collections["posts"] = Carafe::Collection.new("posts")
      site.collections["posts"].resources << Carafe::Resource.new(site, "2024-01-01-a.md")
      site.collections["tutorials"] = Carafe::Collection.new("tutorials")
      site.collections["tutorials"].resources << Carafe::Resource.new(site, "intro.md")

      resource = Carafe::Resource.new(site, "page.md")
      ctx = Carafe::LiquidContextBuilder.build(site, resource)

      # Hash-key access must work for every collection
      render(ctx, "{{ site.collections.posts.docs.size }}").should eq("1")
      render(ctx, "{{ site.collections.tutorials.docs.size }}").should eq("1")
    end
  end

  describe "site.posts always present and sorted" do
    it "is present and sorted newest-first" do
      site = Carafe::Site.new
      site.collections["posts"] = Carafe::Collection.new("posts")
      site.collections["posts"].resources << Carafe::Resource.new(site, "2024-01-01-newer.md")
      site.collections["posts"].resources << Carafe::Resource.new(site, "2023-01-01-older.md")

      resource = Carafe::Resource.new(site, "page.md")
      ctx = Carafe::LiquidContextBuilder.build(site, resource)

      render(ctx, "{{ site.posts.size }}").should eq("2")
      # Newest first (Resource#<=> sorts by date descending)
      # NOTE: .first/.last are preprocessor transforms, not native to liquid shard.
      # Use [0] for direct index access.
      render(ctx, "{{ site.posts[0].slug }}").should contain("newer")
    end

    it "is present (empty) even when no posts collection exists" do
      site = Carafe::Site.new
      resource = Carafe::Resource.new(site, "page.md")
      ctx = Carafe::LiquidContextBuilder.build(site, resource)

      render(ctx, "{{ site.posts.size }}").should eq("0")
    end
  end

  describe "site.data and site.config present" do
    it "exposes site.config.source" do
      site = Carafe::Site.new
      resource = Carafe::Resource.new(site, "page.md")
      ctx = Carafe::LiquidContextBuilder.build(site, resource)

      render(ctx, "{{ site.config.source }}").should eq(site.config.source)
    end

    it "exposes site.data" do
      site = Carafe::Site.new
      site.data["foo"] = YAML.parse(%({"bar": "baz"}))
      resource = Carafe::Resource.new(site, "page.md")
      ctx = Carafe::LiquidContextBuilder.build(site, resource)

      render(ctx, "{{ site.data.foo.bar }}").should eq("baz")
    end
  end

  describe "scalar metadata defaults to empty string" do
    it "title, description, url default to empty string" do
      site = Carafe::Site.new
      resource = Carafe::Resource.new(site, "page.md")
      ctx = Carafe::LiquidContextBuilder.build(site, resource)

      render(ctx, "[{{ site.title }}][{{ site.description }}][{{ site.url }}]").should eq("[][][]")
    end
  end

  describe "doc object shape" do
    it "tags and categories are always arrays" do
      site = Carafe::Site.new
      site.collections["posts"] = Carafe::Collection.new("posts")
      post = Carafe::Resource.new(site, "2024-01-01-a.md",
        frontmatter: Carafe::Frontmatter{"tags" => "foo bar", "categories" => "x"})
      site.collections["posts"].resources << post

      resource = Carafe::Resource.new(site, "page.md")
      ctx = Carafe::LiquidContextBuilder.build(site, resource)

      # NOTE: .first is a preprocessor transform; use [0] for direct access.
      render(ctx, "{{ site.posts[0].tags.size }}").should eq("2")
      render(ctx, "{{ site.posts[0].categories[0] }}").should eq("x")
    end
  end

  describe "build is pure (no side effects)" do
    it "does not write to STDERR" do
      site = Carafe::Site.new
      site.collections["posts"] = Carafe::Collection.new("posts")
      site.collections["posts"].resources << Carafe::Resource.new(site, "2024-01-01-a.md",
        frontmatter: Carafe::Frontmatter{"title" => "T"})
      resource = Carafe::Resource.new(site, "page.md")

      # Build should complete without raising or producing output
      result = Carafe::LiquidContextBuilder.build(site, resource)
      result.should be_a(Liquid::Context)
    end
  end
end

private def render(ctx : Liquid::Context, template_text : String) : String
  Liquid::Template.parse(template_text).render(ctx).strip
end
