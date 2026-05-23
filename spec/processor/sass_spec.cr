require "spec"
require "../spec_helper"
require "../../src/processor/sass"

describe Carafe::Processor::Sass do
  it "renders sass" do
    site = init_site("simple-site")
    processor = Carafe::Processor::Sass.new(site)
    resource = Carafe::Resource.new(nil, "foo.sass")

    result = String.build do |io|
      processor.process(resource, IO::Memory.new("strong\n  color: red\n"), io)
    end

    result.should eq "strong {\n  color: red;\n}\n"
  end
end
