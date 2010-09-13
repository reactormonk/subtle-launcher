#!/usr/bin/ruby
#
# @file Chrome remote
#
# @copyright (c) 2010, Christoph <Kappel unexist@dorfelite.net>
# @version $Id$
#

require "socket"
require "json"
require "uri"

# Chrome remote
class Chromer
  HANDSHAKE = "ChromeDevToolsHandshake\r\n"

  ## initialize {{{
  # Connect to chrome remote shell port
  # @param  [String]  host  Host chrome running on
  # @param  [Fixnum]  port  Remote shell port
  # @raise  [String]  Connection error
  ##

  def initialize(host = "localhost", port = 9222)
    # Connect to socket and send handshake
    @sock = TCPSocket.open(host, port)
    @sock.write(HANDSHAKE)

    # Check reponse
    response = get_response(1)

    unless(HANDSHAKE.chomp.length == response.chomp.length)
      raise "Failed connecting to chrome - handshake error (Got: '%s')" % [
        response.chomp
      ]
    end
  end # }}}

  ## request {{{
  # Send a command to a chrome tool
  # @param  [String]  tool         Chrome tool (DevToolsService or V8Debugger)
  # @param  [String]  destination  Destination tab id
  # @param  [Hash]    args         Argumets for the json request
  #
  # @raise  [Uri::Error]  Uri errors
  ##

  def request(tool, destination = nil, *args)
    response = nil

    # Assemble request
    json     = args.to_json.gsub(/\[(.*)\]/, '\1')
    request  = "Content-Length:%d\r\nTool:%s\r\n" % [ json.size, tool ]
    request << "Destination:%s\r\n" % [ destination ] unless(destination.nil?)
    request << "\r\n%s\r\n" % [ json ]

    @sock.puts(request)

    # Get reponse
    response = get_response(1)

    unless(response.empty?)
      response = response.split("\r\n").last
      response = JSON.parse(response)
    end

    response
  end # }}}

  ## open {{{
  # Open uri in chrome
  # @param  [String]  uri  New uri
  ##

  def open(uri)
    begin
      response = request("DevToolsService", nil, :command => "list_tabs")
      tabs     = response["data"]
      tab      = tabs.last
      tab_id   = tab[0]

      # Check uri
      u = URI.parse(uri)
      u = "http://" + uri if(u.scheme.nil?)

      # Open window
      request("V8Debugger", tab_id,
        :command => "evaluate_javascript",
        :data    => "window.open('%s', '_blank');" % [ u ]
      )
    rescue
      puts ">>> ERROR: Failed sending request"
    end
  end # }}}

  ## close {{{
  # Close connection to chrome
  ##

  def close
    @sock.close
    @sock = nil
  end # }}}

  private

  # get_response {{{
  def get_response(timeout = 0)
    response = ""

    # Handle response
    sets     = select([ @sock ], nil, nil, timeout)
    response = @sock.recv(30000) unless(sets.nil?)

    response
  end # }}}
end
