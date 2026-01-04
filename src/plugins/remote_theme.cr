require "../carafe"
require "http/client"
require "compress/gzip"
require "file_utils"
require "uri"

class Carafe::Plugins::RemoteTheme < Carafe::Plugin
  THEME_CACHE_DIR = ".carafe/themes"

  def name : String
    "remote_theme"
  end

  def version : String
    "0.1.0"
  end

  def enabled?(config : Carafe::Config) : Bool
    # Check if remote_theme is configured in _config.yml
    remote_theme = config["remote_theme"]?
    return false unless remote_theme

    remote_theme_str = remote_theme.as_s?
    return false unless remote_theme_str

    # Validate format (owner/repo)
    parts = remote_theme_str.split('/')
    valid = parts.size == 2 && !parts[0].empty? && !parts[1].empty?
    valid
  end

  def register(site : Carafe::Site) : Nil
    # Add the remote theme generator to the site
    puts "RemoteTheme: Registering generator" unless site.config.quiet?
    site.generators << Generator.new(site)
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

      cache_dir = File.join(site.config.site_dir, THEME_CACHE_DIR, "#{owner}_#{repo}")
      puts "RemoteTheme: Cache dir: #{cache_dir}" unless site.config.quiet?

      # Download or use cached theme
      if File.directory?(cache_dir)
        puts "Using cached remote theme: #{remote_theme}" unless site.config.quiet?
      else
        puts "Downloading remote theme: #{remote_theme}" unless site.config.quiet?
        download_theme(owner, repo, cache_dir, site.config.quiet?)
      end

      # Find the actual theme directory (might be one level deep)
      theme_dir = find_theme_root(cache_dir)
      puts "RemoteTheme: Theme dir: #{theme_dir}" unless site.config.quiet?

      # Integrate theme files
      integrate_theme(theme_dir, site)
    end

    private def find_theme_root(cache_dir : String) : String
      # Check if there's a subdirectory (repo-branch format)
      children = Dir.children(cache_dir)
      if children.size == 1 && File.directory?(File.join(cache_dir, children[0]))
        # Return the subdirectory
        File.join(cache_dir, children[0])
      else
        # Return the cache_dir itself
        cache_dir
      end
    end

    private def download_theme(owner : String, repo : String, theme_dir : String, quiet : Bool) : Nil
      # Create cache directory
      FileUtils.mkdir_p(theme_dir)

      # Use GitHub API to get the default branch
      api_url = "https://api.github.com/repos/#{owner}/#{repo}"
      response = HTTP::Client.get(api_url)

      unless response.status_code == 200
        raise "Failed to fetch repository info for #{owner}/#{repo}: #{response.status_code} #{response.status_message}"
      end

      repo_info = JSON.parse(response.body)
      default_branch = repo_info["default_branch"].as_s

      # Download the repository as tarball
      tarball_url = "https://github.com/#{owner}/#{repo}/archive/refs/heads/#{default_branch}.tar.gz"
      puts "Downloading from: #{tarball_url}" unless quiet

      # Use curl to download (handles redirects automatically)
      temp_file = File.join(theme_dir, "theme.tar.gz")
      process = Process.new("curl", ["-L", "-o", temp_file, tarball_url])
      unless process.wait.success?
        raise "Failed to download theme from #{owner}/#{repo}"
      end

      # Create a temporary directory for extraction
      temp_extract_dir = File.join(theme_dir, "temp_extract")
      FileUtils.mkdir_p(temp_extract_dir)

      # Use tar to extract
      process = Process.new("tar", ["-xzf", temp_file, "-C", temp_extract_dir])
      unless process.wait.success?
        raise "Failed to extract theme tarball"
      end

      # Move the extracted directory contents to theme_dir
      extracted_dirs = Dir.children(temp_extract_dir)
      if extracted_dirs.size == 1
        extracted_root = File.join(temp_extract_dir, extracted_dirs[0])
        FileUtils.cp_r(extracted_root, theme_dir)
      else
        raise "Unexpected tarball structure"
      end

      # Cleanup
      FileUtils.rm_rf(temp_extract_dir)
      File.delete(temp_file)

      puts "Theme downloaded successfully" unless quiet
    rescue ex : Exception
      # Cleanup on failure
      FileUtils.rm_rf(theme_dir) if File.directory?(theme_dir)
      raise "Failed to download remote theme: #{ex.message}"
    end

    private def integrate_theme(theme_dir : String, site : Carafe::Site) : Nil
      # Theme directories to integrate
      theme_dirs = {
        "_layouts"     => site.config.layouts_dir,
        "_includes"    => site.config.includes_dir,
        "_sass"        => "_sass",
        "assets"       => "assets",
        "static"       => "static",
      }

      theme_dirs.each do |theme_subdir, site_subdir|
        source_dir = File.join(theme_dir, theme_subdir)
        target_dir = File.join(site.config.site_dir, site_subdir)

        next unless File.directory?(source_dir)

        # Ensure target directory exists
        FileUtils.mkdir_p(target_dir)

        # Copy files (don't overwrite existing files)
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

      # Copy root-level files (e.g., _config.yml with theme defaults)
      root_files = ["_config.yml", "README.md"]
      root_files.each do |file|
        source_path = File.join(theme_dir, file)
        target_path = File.join(site.config.site_dir, file)

        if File.exists?(source_path) && !File.exists?(target_path)
          # Rename theme config to avoid conflict
          if file == "_config.yml"
            target_path = File.join(site.config.site_dir, "_config_theme.yml")
          end
          FileUtils.cp(source_path, target_path)
        end
      end

      puts "Remote theme integrated successfully" unless site.config.quiet?
    end
  end

  def cleanup(site : Site) : Nil
    # Remove only the cached theme download, not the integrated files
    # The integrated files (_layouts, _includes, etc.) are part of the site source
    theme_cache_dir = File.join(site.config.site_dir, THEME_CACHE_DIR)
    if File.directory?(theme_cache_dir)
      puts "Cleaning up remote theme cache..." unless site.config.quiet?
      FileUtils.rm_rf(theme_cache_dir)
    end
  end
end

# Register this plugin
Carafe::Plugin.register_implementation(Carafe::Plugins::RemoteTheme)
