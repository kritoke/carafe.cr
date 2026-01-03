require "./spec_helper"
require "../src/server"
require "../src/builder"
require "http/client"
require "./support/tempfile"

def wait_for_server_ready(url : String, timeout : Time::Span = 5.seconds)
  started_at = Time.monotonic
  uri = URI.parse(url)
  loop do
    begin
      HTTP::Client.new(uri) do |client|
        client.connect_timeout = 1.second
        client.read_timeout = 1.second
        response = client.get(uri.request_target)
        return # Server is up and responding
      end
    rescue ex : IO::Error | Socket::Error
      # Server not ready or connection refused, continue retrying
    end

    if Time.monotonic - started_at > timeout
      raise "Server at #{url} did not become ready within #{timeout}"
    end

    # Add a small delay before retrying
    sleep 0.05.seconds
  end
end

describe Carafe::Server do
  it "serves files" do
    with_tempdir("server_spec") do |path|
      config = Carafe::Config.load(File.join(FIXTURE_PATH, "simple-site"))
      config.destination = path
      config.port = 4001
      site = Carafe::Site.new(config)
      site.run_generators
      builder = Carafe::Builder.new(site)
      builder.build

      # Verify files exist before starting server
      unless File.exists?(File.join(path, "index.html"))
        puts "Files in #{path}:"
        Dir.glob(File.join(path, "**", "*")).each { |f| puts f }
      end
      File.exists?(File.join(path, "index.html")).should be_true, "index.html missing in #{path}"

      server = Carafe::Server.new(site)
      begin
        spawn { server.start }
        Fiber.yield
        wait_for_server_ready("http://#{site.config.host}:#{site.config.port}/")
        response = HTTP::Client.get("http://#{site.config.host}:#{site.config.port}/")
        response.status_code.should eq(200)
        response.body.should contain("Index")

        response = HTTP::Client.get("http://#{site.config.host}:#{site.config.port}/folder/file.html")
        response.status_code.should eq(200)
        response.body.should contain("file content")

        response = HTTP::Client.get("http://#{site.config.host}:#{site.config.port}/css/site.css")
        response.status_code.should eq(200)
        response.body.should contain("red")
      ensure
        server.close
      end
    end
  end

  it "serves with default config" do
    with_tempdir("server_spec_default") do |path|
      source_dir = File.join(path, "source")
      config = Carafe::Config.new(source_dir)
      config.source = "."
      config.destination = File.join(path, "build")
      config.port = 4002
      FileUtils.mkdir_p(config.destination)
      Dir.mkdir(source_dir)
      File.write(File.join(source_dir, "index.html"), "---\n---\nHello from default")

      site = Carafe::Site.new(config)
      site.run_generators
      Carafe::Builder.new(site).build

      # Verify files exist before starting server
      File.exists?(File.join(config.destination, "index.html")).should be_true, "index.html missing in #{config.destination}"

      server = Carafe::Server.new(site)
      begin
        spawn { server.start }
        Fiber.yield
        wait_for_server_ready("http://#{site.config.host}:#{site.config.port}/index.html")
        response = HTTP::Client.get("http://#{site.config.host}:#{site.config.port}/index.html")
        response.status_code.should eq(200)
        response.body.should contain("Hello from default")
      ensure
        server.close
      end
    end
  end
end
