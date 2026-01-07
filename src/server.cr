require "http/server"
require "./site"

class Carafe::Server
  getter site : Site

  def self.new(site)
    uri = URI.new("tcp", site.config.host, site.config.port, site.config.baseurl)

    new(site, uri)
  end

  def initialize(@site : Site, @uri : String | URI)
    @server = HTTP::Server.new [
      HTTP::ErrorHandler.new,
      Handler.new(@site),
    ]
  end

  def start
    address = @server.bind @uri

    puts "Listening on #{address}"

    @server.listen
  end

  def close
    @server.close
  end

  class Handler
    include HTTP::Handler

    def initialize(@site : Site)
    end

    def call(context : HTTP::Server::Context)
      path = context.request.path

      resource = nil
      if path.empty? || path == "/"
        resource = @site.find("/") || @site.find("/index.html")
      elsif path.ends_with?('/')
        resource = @site.find(path)
        if resource.nil?
          resource = @site.find(path + "index.html")
        end
      elsif path == "/index.html"
        resource = @site.find("/index.html") || @site.find("/")
      elsif !path.includes?('.')
        resource = @site.find(path + ".html")
      else
        resource = @site.find(path)
        if resource.nil? && path.ends_with?(".html")
          path_without_ext = path[0...-5]
          resource = @site.find(path_without_ext)
        end
      end

      unless resource
        context.response.status_code = 404
        context.response.print "Not Found"
        context.response.close
        return
      end

      @site.run_processor(context.response, resource)
      context.response.close
    end
  end

  # DEFAULT_HOST = "0.0.0.0"
  # DEFAULT_PORT = 3000

  # property host : String = DEFAULT_HOST
  # property port : Int32 = DEFAULT_PORT

  # getter! server : HTTP::Server
  # getter site : Site
  # getter! handler : CarafeHandler

  # getattr host, port

  # def initialize(@site)
  # end

  # def start
  #   setup

  #   url = "http://#{host}:#{port}".colorize(:cyan)

  #   begin
  #     server.bind
  #   rescue e : Errno
  #     STDERR.puts "Carafe server could not bind to #{url}"
  #     raise e
  #   end

  #   puts "Carafe server is listening on #{url}"

  #   server.listen
  # end

  # def setup
  #   return unless @server.nil?

  #   @handler = CarafeHandler.new

  #   handlers = [
  #     HTTP::ErrorHandler.new,
  #     LogPrettyHandler.new(STDOUT, colors: site.config.use_colors?),
  #     # HTTP::StaticFileHandler.new(site.source_path, directory_listing: false),
  #     handler,
  #   ]

  #   @server = HTTP::Server.new(host, port, handlers)
  # end
end
