require "spec"
require "../src/server"

describe Carafe::Server::Handler do
  describe "content type mapping" do
    it "returns image/svg+xml for .svg" do
      Carafe::Server::Handler.content_type_for(".svg").should eq("image/svg+xml")
    end

    it "returns text/css for .scss and .sass" do
      Carafe::Server::Handler.content_type_for(".scss").should eq("text/css")
      Carafe::Server::Handler.content_type_for(".sass").should eq("text/css")
    end

    it "returns nil for unknown extensions" do
      Carafe::Server::Handler.content_type_for(".xyz").should be_nil
    end

    it "handles extensions case-insensitively" do
      Carafe::Server::Handler.content_type_for(".SVG").should eq("image/svg+xml")
      Carafe::Server::Handler.content_type_for(".HTML").should eq("text/html")
    end
  end
end
