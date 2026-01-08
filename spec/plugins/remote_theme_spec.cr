require "../spec_helper"
require "http/client"
require "json"

describe Carafe::Plugins::RemoteTheme do
  describe "#enabled?" do
    it "returns false when remote_theme is not set" do
      config = Carafe::Config.new
      plugin = Carafe::Plugins::RemoteTheme.new
      plugin.enabled?(config).should be_false
    end

    it "returns true when remote_theme is set with owner/repo format" do
      config = Carafe::Config.new
      config["remote_theme"] = YAML::Any.new("mmistakes/minimal-mistakes")
      plugin = Carafe::Plugins::RemoteTheme.new
      plugin.enabled?(config).should be_true
    end

    it "returns false when remote_theme has invalid format" do
      config = Carafe::Config.new
      config["remote_theme"] = YAML::Any.new("invalid-format")
      plugin = Carafe::Plugins::RemoteTheme.new
      plugin.enabled?(config).should be_false
    end

    it "returns false when remote_theme has empty owner" do
      config = Carafe::Config.new
      config["remote_theme"] = YAML::Any.new("/repo")
      plugin = Carafe::Plugins::RemoteTheme.new
      plugin.enabled?(config).should be_false
    end

    it "returns false when remote_theme has empty repo" do
      config = Carafe::Config.new
      config["remote_theme"] = YAML::Any.new("owner/")
      plugin = Carafe::Plugins::RemoteTheme.new
      plugin.enabled?(config).should be_false
    end

    it "handles .git suffix in repo name" do
      config = Carafe::Config.new
      config["remote_theme"] = YAML::Any.new("owner/repo.git")
      plugin = Carafe::Plugins::RemoteTheme.new
      plugin.enabled?(config).should be_true
    end
  end

  describe "#register" do
    it "adds RemoteTheme generator to site" do
      config = Carafe::Config.new
      site = Carafe::Site.new(config)
      plugin = Carafe::Plugins::RemoteTheme.new

      plugin.register(site)

      site.generators.size.should be > 0
      site.generators.find { |generator| generator.is_a?(Carafe::Plugins::RemoteTheme::Generator) }.should_not be_nil
    end
  end
end

describe Carafe::Plugins::RemoteTheme::Generator do
  it "has HIGH priority" do
    site = Carafe::Site.new
    generator = Carafe::Plugins::RemoteTheme::Generator.new(site)
    generator.priority.should eq Carafe::Priority::HIGH
  end

  it "does nothing when remote_theme is not configured" do
    site = Carafe::Site.new
    generator = Carafe::Plugins::RemoteTheme::Generator.new(site)

    # Should not raise an error
    generator.generate
  end

  it "caches theme directory" do
    site = Carafe::Site.new
    site.config.site_dir = "/tmp/test_site_#{Time.utc.to_unix}"
    site.config["remote_theme"] = YAML::Any.new("test/repo")

    # Create a mock cached theme directory
    theme_cache_dir = File.join(site.config.site_dir, ".carafe/themes", "test_repo")
    FileUtils.mkdir_p(theme_cache_dir)

    # Create a mock layout
    layouts_dir = File.join(theme_cache_dir, "_layouts")
    FileUtils.mkdir_p(layouts_dir)
    File.write(File.join(layouts_dir, "default.html"), "Layout content")

    generator = Carafe::Plugins::RemoteTheme::Generator.new(site)
    generator.generate

    # Should have copied the layout
    site_layout_dir = File.join(site.config.site_dir, "_layouts")
    File.exists?(File.join(site_layout_dir, "default.html")).should be_true

    # Cleanup
    FileUtils.rm_rf(site.config.site_dir)
  end

  it "integrates theme directories" do
    site = Carafe::Site.new
    site.config.site_dir = "/tmp/test_site_#{Time.utc.to_unix}"
    site.config["remote_theme"] = YAML::Any.new("test/repo")

    # Create a mock cached theme directory
    theme_cache_dir = File.join(site.config.site_dir, ".carafe/themes", "test_repo")
    FileUtils.mkdir_p(theme_cache_dir)

    # Create theme directories with files
    layouts_dir = File.join(theme_cache_dir, "_layouts")
    FileUtils.mkdir_p(layouts_dir)
    File.write(File.join(layouts_dir, "theme.html"), "Theme Layout")

    includes_dir = File.join(theme_cache_dir, "_includes")
    FileUtils.mkdir_p(includes_dir)
    File.write(File.join(includes_dir, "header.html"), "Header content")

    sass_dir = File.join(theme_cache_dir, "_sass")
    FileUtils.mkdir_p(sass_dir)
    File.write(File.join(sass_dir, "theme.scss"), "Theme styles")

    generator = Carafe::Plugins::RemoteTheme::Generator.new(site)
    generator.generate

    # Verify all directories were integrated
    File.exists?(File.join(site.config.site_dir, "_layouts", "theme.html")).should be_true
    File.exists?(File.join(site.config.site_dir, "_includes", "header.html")).should be_true
    File.exists?(File.join(site.config.site_dir, "_sass", "theme.scss")).should be_true

    # Cleanup
    FileUtils.rm_rf(site.config.site_dir)
  end

  it "does not overwrite existing files" do
    site = Carafe::Site.new
    site.config.site_dir = "/tmp/test_site_#{Time.utc.to_unix}"
    site.config["remote_theme"] = YAML::Any.new("test/repo")

    # Create existing layout
    existing_layouts_dir = File.join(site.config.site_dir, "_layouts")
    FileUtils.mkdir_p(existing_layouts_dir)
    existing_content = "Existing layout"
    File.write(File.join(existing_layouts_dir, "default.html"), existing_content)

    # Create a mock cached theme directory
    theme_cache_dir = File.join(site.config.site_dir, ".carafe/themes", "test_repo")
    FileUtils.mkdir_p(theme_cache_dir)

    theme_layouts_dir = File.join(theme_cache_dir, "_layouts")
    FileUtils.mkdir_p(theme_layouts_dir)
    File.write(File.join(theme_layouts_dir, "default.html"), "Theme layout")

    generator = Carafe::Plugins::RemoteTheme::Generator.new(site)
    generator.generate

    # Should have kept existing file
    content = File.read(File.join(site.config.site_dir, "_layouts", "default.html"))
    content.should eq existing_content

    # Cleanup
    FileUtils.rm_rf(site.config.site_dir)
  end

  it "copies theme config as _config_theme.yml" do
    site = Carafe::Site.new
    site.config.site_dir = "/tmp/test_site_#{Time.utc.to_unix}"
    site.config["remote_theme"] = YAML::Any.new("test/repo")

    # Create a mock cached theme directory
    theme_cache_dir = File.join(site.config.site_dir, ".carafe/themes", "test_repo")
    FileUtils.mkdir_p(theme_cache_dir)

    theme_config_content = "theme:\n  name: test-theme"
    File.write(File.join(theme_cache_dir, "_config.yml"), theme_config_content)

    generator = Carafe::Plugins::RemoteTheme::Generator.new(site)
    generator.generate

    # Should have created _config_theme.yml
    theme_config_path = File.join(site.config.site_dir, "_config_theme.yml")
    File.exists?(theme_config_path).should be_true
    File.read(theme_config_path).should eq theme_config_content

    # Cleanup
    FileUtils.rm_rf(site.config.site_dir)
  end
end
