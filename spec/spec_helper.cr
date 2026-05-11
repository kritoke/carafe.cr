require "spec"
require "uri"
require "../src/site"

require "../src/plugins/content/lunr"
require "../src/plugins/navigation/pagination"
require "../src/plugins/themes/remote_theme"

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
