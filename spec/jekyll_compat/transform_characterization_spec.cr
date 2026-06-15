require "../spec_helper"
require "../../src/jekyll_compat"

# Characterization specs for the Jekyll-compat transforms previously performed
# destructively on-disk by TagsPlugin::Generator#process_file.
#
# Evidence base:
#   1. "contains" operator is natively supported by the liquid shard — no
#      transform needed (TagsPlugin's rewrite was redundant).
#   2. "include_cached" cannot be registered as a block alias because the
#      liquid parser's STATEMENT regex ([a-z]+) does not accept underscores.
#      The transform must happen in-memory before parsing.
describe "Jekyll-compat transform characterization" do
  describe "contains operator" do
    it "liquid shard supports 'contains' natively in if-conditions" do
      template = Liquid::Template.parse(%({% if "hello" contains "ell" %}yes{% else %}no{% endif %}))
      template.render(Liquid::Context.new).strip.should eq("yes")
    end

    it "contains returns false when substring is absent" do
      template = Liquid::Template.parse(%({% if "hello" contains "xyz" %}yes{% else %}no{% endif %}))
      template.render(Liquid::Context.new).strip.should eq("no")
    end
  end

  describe "include_cached transform" do
    it "Preprocessor rewrites include_cached to include" do
      input = "{% include_cached foo.html %}"
      result = Carafe::JekyllCompat::Preprocessor.preprocess(input)
      result.should eq("{% include foo.html %}")
    end

    it "Preprocessor preserves include_cached with parameters" do
      input = %{{% include_cached nav.html active="home" %}}
      result = Carafe::JekyllCompat::Preprocessor.preprocess(input)
      result.should eq(%({% include nav.html active="home" %}))
    end

    it "regular include is not affected" do
      input = "{% include foo.html %}"
      result = Carafe::JekyllCompat::Preprocessor.preprocess(input)
      result.should eq("{% include foo.html %}")
    end

    it "renders include_cached via Layout processor (end-to-end)" do
      site = Carafe::Site.new
      resource = Carafe::Resource.new(site, "foo.md", frontmatter: Carafe::Frontmatter{"layout" => "include_cached"})
      processor = Carafe::Processor::Layout.new(
        site,
        layouts_path: "spec/fixtures/simple-site/_layouts",
        includes_path: "spec/fixtures/simple-site/_includes"
      )

      io = IO::Memory.new
      processor.process(resource, IO::Memory.new("content"), io).should be_true
      io.to_s.strip.should eq("FOO included\n\ncontent")
    end
  end
end
