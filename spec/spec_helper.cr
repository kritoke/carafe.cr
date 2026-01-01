require "spec"
require "../src/site"

def init_site(site_dir : String = ".")
  config = Carafe::Config.new(File.join(__DIR__, "fixtures", site_dir))

  Carafe::Site.new(config)
end

def load_site(site_dir : String = ".")
  site = init_site(site_dir)
  site.run_generators

  site
end
