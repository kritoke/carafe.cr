require "spec"
require "../../src/jekyll_compat/preprocessor"

describe Carafe::JekyllCompat::Preprocessor do
  describe "remove_for_modifiers" do
    it "removes offset: from for loops" do
      input = "{% for crumb in crumbs offset: 1 %}x{% endfor %}"
      expected = "{% for crumb in crumbs %}x{% endfor %}"
      result = Carafe::JekyllCompat::Preprocessor.preprocess(input)
      result.should eq(expected)
    end

    it "removes limit: from for loops" do
      input = "{% for item in items limit: 5 %}x{% endfor %}"
      expected = "{% for item in items %}x{% endfor %}"
      result = Carafe::JekyllCompat::Preprocessor.preprocess(input)
      result.should eq(expected)
    end

    it "removes reversed from for loops" do
      input = "{% for item in items reversed %}x{% endfor %}"
      expected = "{% for item in items %}x{% endfor %}"
      result = Carafe::JekyllCompat::Preprocessor.preprocess(input)
      result.should eq(expected)
    end

    it "handles multiple modifiers" do
      input = "{% for item in items limit: 5 offset: 2 reversed %}x{% endfor %}"
      expected = "{% for item in items %}x{% endfor %}"
      result = Carafe::JekyllCompat::Preprocessor.preprocess(input)
      result.should eq(expected)
    end

    it "handles for loop with only offset" do
      input = "{% for crumb in crumbs offset: 1 %}"
      expected = "{% for crumb in crumbs %}"
      result = Carafe::JekyllCompat::Preprocessor.preprocess(input)
      result.should eq(expected)
    end

    it "does not modify for loops without modifiers" do
      input = "{% for item in items %}x{% endfor %}"
      result = Carafe::JekyllCompat::Preprocessor.preprocess(input)
      result.should eq(input)
    end

    it "handles complex template with for loops" do
      input = "{% if true %}{% for crumb in crumbs offset: 1 %}x{% endfor %}{% endif %}"
      expected = "{% if true %}{% for crumb in crumbs %}x{% endfor %}{% endif %}"
      result = Carafe::JekyllCompat::Preprocessor.preprocess(input)
      result.should eq(expected)
    end
  end

  describe "remove_unsupported_filters" do
    it "removes where_exp filter" do
      input = "{% assign x = y | where_exp: \"item\", \"item > 0\" %}"
      expected = "{% assign x = y %}"
      result = Carafe::JekyllCompat::Preprocessor.preprocess(input)
      result.strip.should eq(expected)
    end

    it "removes sort filter" do
      input = "{% assign sorted = items | sort: \"title\" %}"
      expected = "{% assign sorted = items %}"
      result = Carafe::JekyllCompat::Preprocessor.preprocess(input)
      result.strip.should eq(expected)
    end

    it "removes reverse filter" do
      input = "{% assign reversed = items | reverse %}"
      expected = "{% assign reversed = items %}"
      result = Carafe::JekyllCompat::Preprocessor.preprocess(input)
      result.strip.should eq(expected)
    end
  end

  describe "remove_continue_tags" do
    it "removes continue tags" do
      input = "{% for item in items %}{% continue %}{% endfor %}"
      expected = "{% for item in items %}{% endfor %}"
      result = Carafe::JekyllCompat::Preprocessor.preprocess(input)
      result.should eq(expected)
    end
  end

  describe "normalize_ranges" do
    it "preserves literal ranges unchanged" do
      input = "{% for i in (1..10) %}{{ i }}{% endfor %}"
      result = Carafe::JekyllCompat::Preprocessor.preprocess(input)
      result.should contain("(1..10)")
    end

    it "preserves variable ranges unchanged" do
      input = "{% for i in (1..page.limit) %}{{ i }}{% endfor %}"
      result = Carafe::JekyllCompat::Preprocessor.preprocess(input)
      result.should contain("(1..page.limit)")
    end

    it "removes reversed from ranges" do
      input = "{% for i in (1..10) reversed %}{{ i }}{% endfor %}"
      result = Carafe::JekyllCompat::Preprocessor.preprocess(input)
      result.should contain("(1..10)")
      result.should_not contain("reversed")
    end
  end

  describe "convert_dot_accessors" do
    it "converts .last to [1]" do
      input = "{{ items.last }}"
      expected = "{{ items[1] }}"
      result = Carafe::JekyllCompat::Preprocessor.preprocess(input)
      result.should eq(expected)
    end

    it "converts .first to [0]" do
      input = "{{ items.first }}"
      expected = "{{ items[0] }}"
      result = Carafe::JekyllCompat::Preprocessor.preprocess(input)
      result.should eq(expected)
    end
  end
end