require "./spec_helper"
require "../src/server"
require "../src/builder"

private def send_request(handler : Carafe::Server::Handler, url : String) : HTTP::Client::Response
  request = HTTP::Request.new("GET", url)
  io = IO::Memory.new
  response = HTTP::Server::Response.new(io)
  context = HTTP::Server::Context.new(request, response)

  handler.call(context)
  response.close

  io.rewind
  HTTP::Client::Response.from_io(io)
end

describe Carafe::Server do
  it do
    site = load_site("simple-site")

    site.run_generators
    Carafe::Builder.new(site.config.destination).build(site)

    handler = Carafe::Server::Handler.new(site)

    response = send_request(handler, "/2017/08/07/markdown/")
    response.success?.should be_true
    response.body.should eq File.read(File.join(site.site_dir, "/_build/2017/08/07/markdown.html"))
  end
end
