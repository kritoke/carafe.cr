require "spec"
require "../src/pipeline"

describe Carafe::Pipeline do
  it "#pipe" do
    site = Carafe::Site.new
    processors = [
      Carafe::Processor::Liquid.new(site),
      Carafe::Processor::Markdown.new(site),
    ]
    pipeline = Carafe::Pipeline.new processors

    resource = Carafe::Resource.new(site, "sample.md", "Foo **{{ page }}**")
    pipeline.pipe(resource).should eq "<p>Foo <strong>sample.md</strong></p>\n"
  end
end

describe Carafe::Pipeline::Builder do
  it "init" do
    site = Carafe::Site.new
    Carafe::Pipeline::Builder.new(site)
  end

  it "#create_pipeline" do
    site = Carafe::Site.new
    builder = Carafe::Pipeline::Builder.new(site)

    builder.create_pipeline("markdown").processors.map(&.class).should eq [
      Carafe::Processor::Markdown,
      Carafe::Processor::Layout,
    ]
    builder.create_pipeline("jinja.markdown").processors.map(&.class).should eq [
      Carafe::Processor::Liquid,
      Carafe::Processor::Markdown,
      Carafe::Processor::Layout,
    ]
    builder.create_pipeline("sass").processors.map(&.class).should eq [
      Carafe::Processor::Sass,
      Carafe::Processor::Layout,
    ]
    builder.create_pipeline("jinja.html").processors.map(&.class).should eq [
      Carafe::Processor::Liquid,
      Carafe::Processor::Layout,
    ]
  end

  it "#format_for" do
    site = Carafe::Site.new
    builder = Carafe::Pipeline::Builder.new(site)

    resource = Carafe::Resource.new(site, "sample.md", "Foo **{{ page }}**")
    builder.format_for(resource).should eq "liquid.markdown"
  end

  it "#format_for_filename" do
    site = Carafe::Site.new
    builder = Carafe::Pipeline::Builder.new(site)
    builder.format_for_filename("foo.md").should eq "markdown"
  end

  it "#output_ext" do
    site = Carafe::Site.new
    builder = Carafe::Pipeline::Builder.new(site)

    builder.output_ext(".scss").should eq ".css"
    builder.output_ext(".sass").should eq ".css"
    builder.output_ext(".css").should be_nil
    builder.output_ext(".html").should be_nil
    builder.output_ext(".md").should eq ".html"
    builder.output_ext(".markdown").should eq ".html"
    builder.output_ext(".jpg").should be_nil
  end

  it "#output_ext_for" do
    site = Carafe::Site.new
    builder = Carafe::Pipeline::Builder.new(site)

    builder.output_ext_for(Carafe::Resource.new(site, "bar.sass", frontmatter: Carafe::Frontmatter.new)).should eq ".css"
    builder.output_ext_for(Carafe::Resource.new(site, "bar.sass", frontmatter: nil)).should eq ".sass"

    builder.output_ext_for(Carafe::Resource.new(site, "bar.scss", frontmatter: Carafe::Frontmatter.new)).should eq ".css"
    builder.output_ext_for(Carafe::Resource.new(site, "bar.scss", frontmatter: nil)).should eq ".scss"

    builder.output_ext_for(Carafe::Resource.new(site, "bar.css", frontmatter: Carafe::Frontmatter.new)).should eq ".css"
    builder.output_ext_for(Carafe::Resource.new(site, "bar.html", frontmatter: Carafe::Frontmatter.new)).should eq ".html"
  end
end
