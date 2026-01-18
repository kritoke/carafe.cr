class Carafe::Generator::Files < Carafe::Generator
  getter priority : Priority = Priority::HIGH

  def initialize(@site : Site)
  end

  def generate : Nil
    search_path = File.expand_path(site.config.source, site.site_dir)
    Files.load_files(File.join(search_path, "**/*"), search_path, excludes: site.config.exclude, includes: site.config.include) do |slug, content, frontmatter|
      defaults = site.defaults_for(slug, "pages")
      resource = Carafe::Resource.new(site, slug, content, frontmatter: frontmatter, defaults: defaults)
      resource.url = Carafe::Resource.url_for(resource)

      site.files << resource
    end
  end

  def self.load_files(glob, directory, excludes = [] of String, includes = [] of String, &)
    Dir.glob(glob) do |full_path|
      next if File.directory?(full_path)

      slug = full_path.lchop(directory).lchop('/')

      if !includes.any? { |pattern| File.match?(pattern, slug) } && (
           slug.starts_with?('_') && !slug.starts_with?("_pages/") ||
           # Filter out paths with "/_" to skip hidden directories (those starting with "_")
           # Note: Dir.glob("**/*") doesn't skip hidden dirs, so we filter afterward
           # Optimization: Could use recursive directory traversal to avoid this
           slug.includes?("/_") && !slug.starts_with?("_pages/") ||
           excludes.any? { |pattern| File.match?(pattern, slug) }
         )
        next
      end

      begin
        frontmatter, content = load_content(full_path)

        yield slug, content, frontmatter
      rescue ex
        raise Exception.new("Error in #{self.class.name} for file #{slug} (#{directory})", cause: ex)
      end
    end
  end

  def self.load_content(file_path) : {Frontmatter?, String}
    unless File.exists?(file_path)
      raise "File missing #{file_path}"
    end

    File.open(file_path, "r") do |file|
      frontmatter = Frontmatter.read_frontmatter(file)
      content = file.gets_to_end

      {frontmatter, content}
    end
  end
end
