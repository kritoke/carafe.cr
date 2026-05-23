require "../plugin"
require "http/client"
require "compress/gzip"
require "file_utils"
require "uri"

class Carafe::Plugins::RemoteThemePlugin < Carafe::Plugin
  THEME_CACHE_DIR = ".carafe/themes"
  OWNER_REPO_REGEX = /\A[a-zA-Z0-9._-]+\z/

  def name : String
    "remote_theme"
  end

  def version : String
    "0.1.0"
  end

  def enabled?(config : Carafe::Config) : Bool
    remote_theme = config["remote_theme"]?
    return false unless remote_theme

    remote_theme_str = remote_theme.as_s?
    return false unless remote_theme_str

    parts = remote_theme_str.split('/')
    parts.size == 2 && !parts[0].empty? && !parts[1].empty?
  end

  def register(site : Carafe::Site) : Nil
    puts "RemoteTheme: Registering generator" unless site.config.quiet?
    site.generators << Generator.new(site)
  end

  def cleanup(site : Carafe::Site) : Nil
    # Theme cache is kept between builds for performance
    # The cache is only cleaned if explicitly requested
  end

  class Generator < Carafe::Generator
    getter priority : Carafe::Priority = Carafe::Priority::HIGH

    def initialize(site : Carafe::Site)
      super(site)
    end

    def generate : Nil
      remote_theme = site.config["remote_theme"]?.try(&.as_s)
      return unless remote_theme

      puts "RemoteTheme: Processing theme #{remote_theme}" unless site.config.quiet?

      parts = remote_theme.split('/')
      owner = parts[0]
      repo = parts[1].sub(/\.git$/, "")

      # Validate owner and repo format to prevent injection
      unless OWNER_REPO_REGEX =~ owner && OWNER_REPO_REGEX =~ repo
        raise "Invalid owner or repository name format in remote_theme: #{remote_theme}"
      end

      cache_dir = File.join(site.config.site_dir, THEME_CACHE_DIR, "#{owner}_#{repo}")
      puts "RemoteTheme: Cache dir: #{cache_dir}" unless site.config.quiet?

      if File.directory?(cache_dir)
        puts "Using cached remote theme: #{remote_theme}" unless site.config.quiet?
      else
        puts "Downloading remote theme: #{remote_theme}" unless site.config.quiet?
        download_theme(owner, repo, cache_dir, site.config.quiet?)
      end

      theme_dir = find_theme_root(cache_dir)
      puts "RemoteTheme: Theme dir: #{theme_dir}" unless site.config.quiet?

      integrate_theme(theme_dir, site)
    end

    private def find_theme_root(cache_dir : String) : String
      children = Dir.children(cache_dir)
      if children.size == 1 && File.directory?(File.join(cache_dir, children[0]))
        File.join(cache_dir, children[0])
      else
        cache_dir
      end
    end

    private def download_theme(owner : String, repo : String, theme_dir : String, quiet : Bool) : Nil
      FileUtils.mkdir_p(theme_dir)

      api_url = "https://api.github.com/repos/#{owner}/#{repo}"
      response = HTTP::Client.get(api_url)

      unless response.status_code == 200
        raise "Failed to fetch repository info for #{owner}/#{repo}: #{response.status_code} #{response.status_message}"
      end

      repo_info = JSON.parse(response.body)
      default_branch = repo_info["default_branch"].as_s

      tarball_url = "https://github.com/#{owner}/#{repo}/archive/refs/heads/#{default_branch}.tar.gz"
      puts "Downloading from: #{tarball_url}" unless quiet

      temp_file = File.join(theme_dir, "theme.tar.gz")
      process = Process.new("curl", ["-L", "-o", temp_file, tarball_url])
      unless process.wait.success?
        raise "Failed to download theme from #{owner}/#{repo}"
      end

      temp_extract_dir = File.join(theme_dir, "temp_extract")
      FileUtils.mkdir_p(temp_extract_dir)

      process = Process.new("tar", ["-xzf", temp_file, "-C", temp_extract_dir])
      unless process.wait.success?
        raise "Failed to extract theme tarball"
      end

      extracted_dirs = Dir.children(temp_extract_dir)
      if extracted_dirs.size == 1
        extracted_root = File.join(temp_extract_dir, extracted_dirs[0])
        FileUtils.cp_r(extracted_root, theme_dir)
      else
        raise "Unexpected tarball structure"
      end

      FileUtils.rm_rf(temp_extract_dir)
      File.delete(temp_file)

      puts "Theme downloaded successfully" unless quiet
    rescue ex : Exception
      FileUtils.rm_rf(theme_dir) if File.directory?(theme_dir)
      raise "Failed to download remote theme: #{ex.message}"
    end

    private def integrate_theme(theme_dir : String, site : Carafe::Site) : Nil
      theme_dirs = {
        "_layouts"  => site.config.layouts_dir,
        "_includes" => site.config.includes_dir,
        "_sass"     => "_sass",
        "assets"    => "assets",
        "static"    => "static",
      }

      theme_dirs.each do |theme_subdir, site_subdir|
        source_dir = File.join(theme_dir, theme_subdir)
        target_dir = File.join(site.config.site_dir, site_subdir)

        next unless File.directory?(source_dir)

        FileUtils.mkdir_p(target_dir)

        Dir.each_child(source_dir) do |item|
          source_path = File.join(source_dir, item)
          target_path = File.join(target_dir, item)

          unless File.exists?(target_path)
            if File.directory?(source_path)
              FileUtils.cp_r(source_path, target_path)
            else
              FileUtils.cp(source_path, target_path)
            end
          end
        end
      end

      root_files = ["_config.yml", "README.md"]
      root_files.each do |file|
        source_path = File.join(theme_dir, file)
        target_path = File.join(site.config.site_dir, file)

        if File.exists?(source_path) && !File.exists?(target_path)
          if file == "_config.yml"
            target_path = File.join(site.config.site_dir, "_config_theme.yml")
          end
          FileUtils.cp(source_path, target_path)
        end
      end

      puts "Remote theme integrated successfully" unless site.config.quiet?
    end
  end
end

Carafe::Plugin.register_implementation(Carafe::Plugins::RemoteThemePlugin)
