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
    begin
      address = @server.bind @uri
      puts "Listening on #{address}"
      @server.listen
    rescue ex
      msg = ex.message || ""
      if ex.is_a?(Errno) || msg.includes?("address already in use") || msg.includes?("Permission denied")
        # Get port from uri
        port = @uri.is_a?(String) ? @uri : @uri.as(URI).port
        if msg.includes?("address already in use") || (ex.is_a?(Errno) && ex.errno == Errno::EADDRINUSE)
          STDERR.puts "Error: Port #{port} is already in use."
          STDERR.puts "Try specifying a different port with --port=PORT"
        elsif msg.includes?("Permission denied") || (ex.is_a?(Errno) && ex.errno == Errno::EACCES)
          STDERR.puts "Error: Permission denied to bind to port #{port}."
          STDERR.puts "Try using a port above 1024"
        else
          STDERR.puts "Error: Server could not bind to #{@uri}"
          STDERR.puts msg
        end
      end
      raise ex
    end
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
        # Fallback: serve static files from _site directory
        dest_dir = File.join(@site.site_dir, @site.config.destination)
        static_path = File.join(dest_dir, path)
        if File.exists?(static_path) && !File.directory?(static_path)
          ext = File.extname(static_path).downcase
          content_type = case ext
                        when ".json" then "application/json"
                        when ".css" then "text/css"
                        when ".js" then "application/javascript"
                        when ".html" then "text/html"
                        when ".xml" then "application/xml"
                        when ".txt" then "text/plain"
                        else "application/octet-stream"
                        end
          context.response.content_type = content_type
          context.response.print File.read(static_path)
          context.response.close
          return
        end

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
