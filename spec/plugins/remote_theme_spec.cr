require "../spec_helper"
require "http/client"
require "json"

describe Carafe::Plugins::RemoteThemePlugin do
  describe "#enabled?" do
    it "returns false when remote_theme is not set" do
      config = Carafe::Config.new
      plugin = Carafe::Plugins::RemoteThemePlugin.new
      plugin.enabled?(config).should be_false
    end

    it "returns true when remote_theme is set with owner/repo format" do
      config = Carafe::Config.new
      config["remote_theme"] = YAML::Any.new("mmistakes/minimal-mistakes")
      plugin = Carafe::Plugins::RemoteThemePlugin.new
      plugin.enabled?(config).should be_true
    end

    it "returns false when remote_theme has invalid format" do
      config = Carafe::Config.new
      config["remote_theme"] = YAML::Any.new("invalid-format")
      plugin = Carafe::Plugins::RemoteThemePlugin.new
      plugin.enabled?(config).should be_false
    end

    it "returns false when remote_theme has empty owner" do
      config = Carafe::Config.new
      config["remote_theme"] = YAML::Any.new("/repo")
      plugin = Carafe::Plugins::RemoteThemePlugin.new
      plugin.enabled?(config).should be_false
    end

    it "returns false when remote_theme has empty repo" do
      config = Carafe::Config.new
      config["remote_theme"] = YAML::Any.new("owner/")
      plugin = Carafe::Plugins::RemoteThemePlugin.new
      plugin.enabled?(config).should be_false
    end

    it "handles .git suffix in repo name" do
      config = Carafe::Config.new
      config["remote_theme"] = YAML::Any.new("owner/repo.git")
      plugin = Carafe::Plugins::RemoteThemePlugin.new
      plugin.enabled?(config).should be_true
    end
  end

  describe "#register" do
    it "adds RemoteTheme generator to site" do
      config = Carafe::Config.new
      site = Carafe::Site.new(config)
      plugin = Carafe::Plugins::RemoteThemePlugin.new

      plugin.register(site)

      site.generators.size.should be > 0
      site.generators.find { |generator| generator.is_a?(Carafe::Plugins::RemoteThemePlugin::Generator) }.should_not be_nil
    end
  end
end

describe Carafe::Plugins::RemoteThemePlugin::Generator do
  it "has HIGH priority" do
    site = Carafe::Site.new
    generator = Carafe::Plugins::RemoteThemePlugin::Generator.new(site)
    generator.priority.should eq Carafe::Priority::HIGH
  end

  it "does nothing when remote_theme is not configured" do
    site = Carafe::Site.new
    generator = Carafe::Plugins::RemoteThemePlugin::Generator.new(site)

    generator.generate
  end

  it "caches theme directory" do
    site_dir = "/tmp/test_site_#{Time.utc.to_unix}"
    FileUtils.mkdir_p(site_dir)

    theme_cache_dir = File.join(site_dir, ".carafe/themes", "test_repo")
    FileUtils.mkdir_p(theme_cache_dir)

    theme_subdir = File.join(theme_cache_dir, "repo-main")
    FileUtils.mkdir_p(theme_subdir)

    layouts_dir = File.join(theme_subdir, "_layouts")
    FileUtils.mkdir_p(layouts_dir)
    File.write(File.join(layouts_dir, "default.html"), "Layout content")

    site = Carafe::Site.new
    site.config.site_dir = site_dir
    site.config["remote_theme"] = YAML::Any.new("test/repo")

    generator = Carafe::Plugins::RemoteThemePlugin::Generator.new(site)
    generator.generate

    site_layout_dir = File.join(site.config.site_dir, "_layouts")
    File.exists?(File.join(site_layout_dir, "default.html")).should be_true

    FileUtils.rm_rf(site.config.site_dir)
  end

  it "integrates theme directories" do
    site = Carafe::Site.new
    site.config.site_dir = "/tmp/test_site_#{Time.utc.to_unix}"
    site.config["remote_theme"] = YAML::Any.new("test/repo")

    theme_cache_dir = File.join(site.config.site_dir, ".carafe/themes", "test_repo")
    FileUtils.mkdir_p(theme_cache_dir)

    layouts_dir = File.join(theme_cache_dir, "_layouts")
    FileUtils.mkdir_p(layouts_dir)
    File.write(File.join(layouts_dir, "theme.html"), "Theme Layout")

    includes_dir = File.join(theme_cache_dir, "_includes")
    FileUtils.mkdir_p(includes_dir)
    File.write(File.join(includes_dir, "header.html"), "Header content")

    sass_dir = File.join(theme_cache_dir, "_sass")
    FileUtils.mkdir_p(sass_dir)
    File.write(File.join(sass_dir, "theme.scss"), "Theme styles")

    generator = Carafe::Plugins::RemoteThemePlugin::Generator.new(site)
    generator.generate

    File.exists?(File.join(site.config.site_dir, "_layouts", "theme.html")).should be_true
    File.exists?(File.join(site.config.site_dir, "_includes", "header.html")).should be_true
    File.exists?(File.join(site.config.site_dir, "_sass", "theme.scss")).should be_true

    FileUtils.rm_rf(site.config.site_dir)
  end

  it "does not overwrite existing files" do
    site = Carafe::Site.new
    site.config.site_dir = "/tmp/test_site_#{Time.utc.to_unix}"
    site.config["remote_theme"] = YAML::Any.new("test/repo")

    existing_layouts_dir = File.join(site.config.site_dir, "_layouts")
    FileUtils.mkdir_p(existing_layouts_dir)
    existing_content = "Existing layout"
    File.write(File.join(existing_layouts_dir, "default.html"), existing_content)

    theme_cache_dir = File.join(site.config.site_dir, ".carafe/themes", "test_repo")
    FileUtils.mkdir_p(theme_cache_dir)

    theme_layouts_dir = File.join(theme_cache_dir, "_layouts")
    FileUtils.mkdir_p(theme_layouts_dir)
    File.write(File.join(theme_layouts_dir, "default.html"), "Theme layout")

    generator = Carafe::Plugins::RemoteThemePlugin::Generator.new(site)
    generator.generate

    content = File.read(File.join(site.config.site_dir, "_layouts", "default.html"))
    content.should eq existing_content

    FileUtils.rm_rf(site.config.site_dir)
  end

  it "copies theme config as _config_theme.yml" do
    site = Carafe::Site.new
    site.config.site_dir = "/tmp/test_site_#{Time.utc.to_unix}"
    site.config["remote_theme"] = YAML::Any.new("test/repo")

    theme_cache_dir = File.join(site.config.site_dir, ".carafe/themes", "test_repo")
    FileUtils.mkdir_p(theme_cache_dir)

    theme_config_content = "theme:\n  name: test-theme"
    File.write(File.join(theme_cache_dir, "_config.yml"), theme_config_content)

    generator = Carafe::Plugins::RemoteThemePlugin::Generator.new(site)
    generator.generate

    theme_config_path = File.join(site.config.site_dir, "_config_theme.yml")
    File.exists?(theme_config_path).should be_true
    File.read(theme_config_path).should eq theme_config_content

    FileUtils.rm_rf(site.config.site_dir)
  end
end
