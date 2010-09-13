#!/usr/bin/ruby
#
# @file Launcher
#
# @copyright (c) 2010, Christoph <Kappel unexist@dorfelite.net>
# @version $Id$
#

begin
  require "subtle/subtlext" unless defined?(Subtle)
  require_relative "levenshtein.rb"
rescue LoadError => err
  puts ">>> ERROR: Missing dependencies"
  puts "           %s" % [ err ]
  exit
end

require "singleton"
require "uri"

module Launcher
  RE_COMMAND  = /(@|\#)[a-z0-9]+/
  RE_URI      = /^(http|https):\/\/[a-z0-9]+([\-\.]{1}[a-z0-9]+)*\.[a-z]{2,5}(([0-9]{1,5})?\/.*)?$/ix
  RE_CHROME   = /chrom[e|ium]|iron/
  RE_FIREFOX  = /navigator/
  RE_OPERA    = /opera/

  # Launcher class
  class Launcher
    include Singleton

    ## initialize {{{
    # Create launcher instance
    ##

    def initialize
      @candidate = nil
      @browser   = nil
      @view      = nil
      @completed = false

      # Cache
      @cache_tags  = Subtlext::Tag.all.map { |t| t.name }
      @cache_views = Subtlext::View.all.map { |v| v.name }
      @cache_apps  = {}

      # Something near a skiplist
      Dir["/usr/bin/*"].each do |a|
        file = File.basename(a)
        sym  = file[0].to_sym

        if(@cache_apps.has_key?(sym))
          @cache_apps[sym] << file
        else
          @cache_apps[sym] = [ file ]
        end
      end

      # Init for performance
      @array1 = Array.new(20, 0)
      @array2 = Array.new(20, 0)

      # Geometry
      geo     = Subtlext::Screen[0].geometry
      @width  = geo.width * 80 / 100
      @height = 90
      @x      = (geo.width - @width) / 2
      @y      = (geo.height - @height) - (@height / 2)

      # Create windows
      @input  = Subtlext::Window.new(:x => 0, :y => 0,
          :width => 1, :height => 1) do |w|
        w.name         = "Launcher: Input"
        w.font         = "xft:Envy Code R:pixelsize=80"
        w.foreground   = Subtlext::Subtle.colors[:fg_focus]
        w.background   = Subtlext::Subtle.colors[:bg_focus]
        w.border_size  = 0
      end

      # Input handler
      @input.input do |string|
        begin
          Launcher.instance.input(string)
        rescue => err
          puts err, err.backtrace
        end
      end

      # Completion handler
      @input.completion do |string, guess|
        begin
          Launcher.instance.completion(string, guess)
        rescue => err
          puts err, err.backtrace
        end
      end

      @info  = Subtlext::Window.new(:x => 0, :y => 0,
          :width => 1, :height => 1) do |w|
        w.name        = "Launcher: Info"
        w.font        = "xft:Envy Code R:pixelsize=12"
        w.foreground  = Subtlext::Subtle.colors[:fg_panel]
        w.background  = Subtlext::Subtle.colors[:bg_panel]
        w.border_size = 0
      end

      move
      info
    end # }}}

    ## input {{{
    # Handle input
    # @param  [String]]  string  Input string
    ##

    def input(string)
      # Clear info field
      if(string.empty? or string.nil?)
        info
        @completed = false
        return
      end

      # Check input
      if(RE_URI.match(string))
        @candidate = URI.parse(string)

        info("Goto %s" % [ @candidate.to_s ])
      elsif(RE_COMMAND.match(string) or @completed)
        @candidate = string

        info("Launcher")
      else
        @candidate = URI.parse("http://www.google.com/#q=%s" % [
           URI.escape(string)
        ])

        info("Goto %s" % [ @candidate.to_s ])
      end
    end # }}}

    ## completion {{{
    # Complete string
    # @param  [String]  string  String to match
    # @param  [Fixnum]  guess   Number of guess
    ##

    def completion(string, guess)
      begin
        guesses = []
        lookup = nil

        # Clear info field
        if(string.empty? or string.nil?)
          info
          @completed = false
          return
        end

        @completed = true

        # Select lookup cache
        last = string.split(" ").last rescue string
        if(last.start_with?("#"))
          lookup = @cache_tags
          prefix = "#"
        elsif(last.start_with?("@"))
          lookup = @cache_views
          prefix = "@"
        else
          lookup = @cache_apps[last[0].to_sym]
          prefix = ""
        end

        # Collect guesses
        unless(lookup.nil?)
          lookup.each do |l|
            guesses << [
              "%s%s" %[ prefix, l ],
              Levenshtein::distance(last.gsub(/^[@#]/, ""),
                l, 1, 5, 5, @array1, @array2)
            ]
          end

          guesses.sort! { |a, b| a[1] <=> b[1] } # Sort for costs

          @candidate = guesses[guess].first
        end
      rescue => err
        puts err, err.backtrace
      end
    end # }}}

    ## move {{{
    # Move gleebox windows to x/y
    # @param  [Fixnum]  x  X position
    # @param  [Fixnum]  y  Y position
    ##

    def move(x = @x, y = @y)
      @x = x
      @y = y

      @input.geometry = [ @x, @y, @width, @height ]
      @info.geometry  = [ @x, @y + @height, @width, 20 ]
    end # }}}

    ## show {{{
    # Show gleebox
    ##

    def show
      @input.show
      @info.show

      info
    end # }}}

    ## hide # {{{
    # Hide gleebox
    ##

    def hide
      @input.hide
      @info.hide
    end # }}}

    ## run {{{
    # Show and run gleebox
    ##

    def run
      show
      ret = @input.read(2, @height - 25, 18)
      hide

      # Check if input returns a value
      unless(ret.nil?)
        case @candidate
          when String # {{{
            tags  = []
            views = []
            spawn = []

            # Parse args
            @candidate.split.each do |arg|
              case arg[0]
                when "#" then tags  << arg[1..-1]
                when "@" then views << arg[1..-1]
                else          spawn << arg
              end
            end

            # Add an ad-hoc tag if we don't have any
            if(not @candidate.empty? and tags.empty? and
                (not spawn.empty? or not views.empty?))
              tags << rand(1337).to_s
            end

            tags.each do |t|
              # Find or create tag
              tag = Subtlext::Tag[t] || Subtlext::Tag.new(t)
              tag.save

              # Spawn app and tag it
              spawn.each do |s|
                pid = Subtlext::Subtle.spawn(s)

                sleep 1 #< Wait for client to appear

                Subtlext::Client[:pid => pid].tag(tag) unless(pid.nil?)
              end

              # Find or create view and add tag
              views.each do |v|
                view = Subtlext::View[v] || Subtlext::View.new(v)
                view.save
                view.tag(tag)
              end
            end # }}}
          when URI # {{{
            find_browser
            unless(@browser.nil?)
              @view.jump

              # Select browser
              case @browser
                when :chrome
                  unless(defined?(Chromer))
                    require_relative "chromer.rb"
                  end

                  chromer = Chromer.new
                  chromer.open(@candidate.to_s)
                  chromer.close
                when :firefox
                  system("firefox -new-tab '%s'" % [ @candidate.to_s ])
                when :opera
                  system("opera -remote 'openURL(%s)'" % [ @candidate.to_s ])
                else
                  puts ">>> ERROR: Unsupported browser"
                  return
              end
            end # }}}
        end
      end

      @candidate = nil
      @completed = false
    end # }}}

    private

    def find_browser # {{{
      begin
        if(@browser.nil?)
          Subtlext::Client.all.each do |c|
            case c.instance
              when RE_CHROME
                @browser = :chrome
                @view    = c.views.first
                return
              when RE_FIREFOX
                @browser = :firefox
                @view    = c.views.first
                return
              when RE_OPERA
                @browser = :opera
                @view    = c.views.first
                return
            end
          end

          puts ">>> ERROR: No supported browser found"
          puts "           (Supported: Chrome, Firefox and Opera)"
        end
      rescue
        @browser = nil
        @view    = nil
      end
    end # }}}

    # info {{{
    def info(string = nil)
      @info.write(2, 15, string || "Nothing selected")
      @info.redraw
    end # }}}
  end
end

# Implicitly run
if(__FILE__ == $0)
  Launcher::Launcher.instance.run
end
