require "spec"
require "../src/frontmatter"

describe Carafe::Frontmatter do
  describe ".read_frontmatter" do
    it "reads frontmatter" do
      io = IO::Memory.new("---\nfoo: bar\n---\ncontent")
      Carafe::Frontmatter.read_frontmatter(io).should eq Carafe::Frontmatter{"foo" => "bar"}

      io.gets_to_end.should eq "content"
    end

    it "reads frontmatter with extra dashes" do
      io = IO::Memory.new("---\nfoo: bar\n------\ncontent")
      Carafe::Frontmatter.read_frontmatter(io).should eq Carafe::Frontmatter{"foo" => "bar"}

      io.gets_to_end.should eq "content"
    end

    it "reads no frontmatter" do
      io = IO::Memory.new("content")
      Carafe::Frontmatter.read_frontmatter(io).should be_nil

      io.gets_to_end.should eq "content"
    end

    it "reads empty frontmatter" do
      io = IO::Memory.new("---\n---\ncontent")
      Carafe::Frontmatter.read_frontmatter(io).should eq Carafe::Frontmatter.new
      io.gets_to_end.should eq "content"
    end

    it "fails when invalid" do
      io = IO::Memory.new("---\n1---\ncontent")
      expect_raises(Exception, "invalid frontmatter") do
        Carafe::Frontmatter.read_frontmatter(io)
      end
    end

    it "fails when invalid delimiter" do
      io = IO::Memory.new("---\n---foo\ncontent")
      expect_raises(Exception, "invalid frontmatter") do
        Carafe::Frontmatter.read_frontmatter(io)
      end
    end

    it "reads frontmatter with CRLF" do
      io = IO::Memory.new("---\r\nfoo: bar\r\n---\r\ncontent")
      Carafe::Frontmatter.read_frontmatter(io).should eq Carafe::Frontmatter{"foo" => "bar"}

      io.gets_to_end.should eq "content"
    end

    it "reads frontmatter with CRLF and extra dashes" do
      io = IO::Memory.new("---\r\nfoo: bar\r\n------\r\ncontent")
      Carafe::Frontmatter.read_frontmatter(io).should eq Carafe::Frontmatter{"foo" => "bar"}

      io.gets_to_end.should eq "content"
    end
  end
end
