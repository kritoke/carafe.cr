require "spec"
require "../src/collection"

describe Carafe::Collection do
  it ".new" do
    collection = Carafe::Collection.new("foo")

    collection.name.should eq "foo"
    collection.resources.should eq [] of Carafe::Resource
  end

  it ".new with config" do
    config = Carafe::Config::Collection.new
    collection = Carafe::Collection.new("foo", config)

    collection.name.should eq "foo"
    collection.resources.should eq [] of Carafe::Resource
    collection.defaults.should eq config
  end
end
