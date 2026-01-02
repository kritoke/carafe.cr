require "spec"
require "../../src/processor/sass"

describe Carafe::Processor::Sass do
  it "renders sass" do
    processor = Carafe::Processor::Sass.new
    resource = Carafe::Resource.new(nil, "foo.sass")

    String.build do |io|
      processor.process(resource, IO::Memory.new("strong\n  color: red\n"), io)
    end.should eq "strong {\n  color: red;\n}\n"
  end
end
