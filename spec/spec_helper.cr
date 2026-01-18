require "spec"
require "uri"
require "../src/site"

# Load plugins
require "../src/plugins/carafe_lunr"
require "../src/plugins/pagination"
require "../src/plugins/remote_theme"

FIXTURE_PATH = File.expand_path("fixtures", __DIR__)

def init_site(site_dir : String = ".")
  config = Carafe::Config.new(File.join(FIXTURE_PATH, site_dir))

  Carafe::Site.new(config)
end

def load_site(site_dir : String = ".")
  site = init_site(site_dir)
  site.run_generators

  site
end
