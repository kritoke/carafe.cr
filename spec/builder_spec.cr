require "spec"
require "../src/builder"
require "./support/tempfile"
require "file_utils"

describe Carafe::Builder do
  it "#build" do
    site = Carafe::Site.new
    site.files << Carafe::Resource.new(site, "sample.md", "Foo **{{ page.name }}**")

    with_tempfile("builder") do |output_path|
      builder = Carafe::Builder.new(output_path)
      builder.build(site)
    end
  end
end
