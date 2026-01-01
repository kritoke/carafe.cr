require "spec"
require "../../src/processor/markdown"

describe Carafe::Processor::Markdown do
  it "renders markdown" do
    processor = Carafe::Processor::Markdown.new
    resource = Carafe::Resource.new(nil, "foo.md")

    String.build do |io|
      processor.process(resource, IO::Memory.new("Foo *bar*"), io)
    end.should eq "<p>Foo <em>bar</em></p>\n"
  end
end
