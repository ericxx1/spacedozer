#!/usr/bin/env ruby
# encoding: utf-8

# space dozer
#
# Gino Lucero
# http://github.com/glucero
# glucero@gmail.com
#
# aliens are attacking and you are the construction yard's last line of defense

Settings = {

  :refresh => 0.05, # 5/100th of a second
  :turn    => 0.50, # 1/2 second

  :warps => 0.05, # these settings need
  :spawn => {     # to be refactored
    :rock     => 0.005, #
    :dirt     => 0.50,  # spawn settings are a percentage of
    :warpgate => 0.01,  # all possible locations and are additive
    :alien    => 0.001  #
    },

  :iconmap => {
    :rock      => '☗', # an immovable block
    :dirt      => '☖', # a movable block
    :warpgate  => '♨', # a warp gate, spawns aliens
    :alien     => '☄', # moves randomly, spawns warp gates sometimes
    :dozer     => '✧', # you, the bulldozer

    :dozer_icons => {
      :right => '⫣',  #
      :left  => '⫦',  # use icon based on last turn
      :up    => '⫧',  # in the future
      :down  => '⫨'   #
    }
  },

  :keymap => {
    27  => :stop, # <Esc> key
    'x' => :stop, # quit and exit the game

    'k' => :up,   #
    'j' => :down, # move the bulldozer
    'h' => :left, #
    'l' => :right #
  },

  :start  => Time.now,
  :score  => 0

}

module SpaceDozer

  require 'curses'

  class Game

    def rocks; @rocks ||= [] end
    def dirts; @dirts ||= [] end  # hooray for grammarz
    def warpgates; @warpgates ||= [] end
    def aliens; @aliens ||= [] end
    def dozer; @dozer ||= Dozer.new(self) end

    def running?; @running         end
    def stop;     @running = false end

    def center; [width / 2,   height / 2]   end
    def random; [rand(width), rand(height)] end

    def width
      @width ||= (Curses.lines > 50) ? 50 : Curses.lines
    end

    def height
      @height ||= (Curses.cols > 150) ? 150 : Curses.cols
    end

    def refresh
      wipe
      rocks.each(&:draw)
      dirts.each(&:draw)
      warpgates.each(&:draw)
      aliens.each(&:draw)
      dozer.draw

      Curses.refresh
    end

    def wipe
      Curses.setpos(0, 0)
      height.times { Curses.deleteln }
    end

    def up;    dozer.up    end
    def down;  dozer.down  end
    def left;  dozer.left  end
    def right; dozer.right end

    def listen_for_keypress
      if (keypress = Settings[:keymap][Curses.getch])
        send keypress
      end
    end

    def start
      @running = true
      @time = Time.now

      while running?
        return(stop) if dozer.dead?

        listen_for_keypress

        warpgates.reject!(&:dead?)
        aliens.reject!(&:dead?)

        if (Time.now - @turn) > Settings[:turn]
          warpgates.select(&:full_power?).each(&:activate)

          aliens.each(&:spawn)
          aliens.each(&:move)
          return(stop) if dozer.dead?

          @turn = Time.now
        end

        refresh
        sleep Settings[:refresh]
      end
    end

    def spawn(type, x, y)
      entity = SpaceDozer.const_get(type.capitalize).new(self, [x, y])
      collection = send("#{type}s")

      collection << entity unless dozer === entity
    end

    def initialize
      Curses.init_screen         # clear and init screen
      Curses.noecho              # don't echo keypresses
      Curses.curs_set(0)         # hide cursor
      Curses.cbreak              # turn off line buffering
      Curses.stdscr.nodelay = -1 # don't wait for input, just listen for it

      # fix me. i'm spawning blocks ontop of blocks
      Settings[:spawn].each do |type, count|
        (width * height * count).to_i.times do
          entity = SpaceDozer.const_get(type.capitalize).new(self)
          collection = send("#{type}s")

          # unless (type == :block || type == :rock) && (collection && collection.find { |e| e === entity })
          unless (type == :block || type == :rock) && (collection && collection.find { |e| e === entity })
            collection << entity
          end
        end
      end

      @turn = Time.now

      yield self
    end
  end

  class Entity # change my name

    attr_reader :game,
                :x,
                :y

    def up!;    @x -= 1 end
    def down!;  @x += 1 end
    def left!;  @y -= 1 end
    def right!; @y += 1 end

    def up;    up!    if can_move? :up!    end
    def down;  down!  if can_move? :down!  end
    def left;  left!  if can_move? :left!  end
    def right; right! if can_move? :right! end

    def dead?; @dead end

    def kill
      Curses.setpos(x, y)
      Curses.delch
      @dead = true
    end

    def draw
      Curses.setpos(x, y)
      Curses.addstr(body)
    end

    def from(location)
      self.dup.tap do |entity|
        entity.send location

        return !!(yield entity)
      end
    end

    def can_move?(location)
      from(location) do |entity|
        return false if entity.out_of_bounds?
        return false if game.rocks.find { |rock| rock === entity }

        if (warpgate = game.warpgates.find { |warpgate| warpgate === entity })
          case entity
          when Dirt then warpgate.kill
          end

        elsif (dirt = game.dirts.find { |dirt| dirt === entity })
          unless Alien === entity # aliens can't move blocks
            dirt.send location if dirt.can_move? location
          end
        elsif (alien = game.aliens.find { |alien| alien === entity })
          case entity
          when Dirt
            unless alien.can_move? location
              alien.kill
            end
          when Dozer then game.dozer.kill
          end
        elsif (Dirt === entity || Alien === entity) && (game.dozer === entity)
          # the above elsif isn't corrent
          game.dozer.kill
        else
          true
        end
      end
    end

    def ===(entity)
      (x == entity.x && y == entity.y)
    end

    def name
      @name ||= self.class.name.downcase.split(':').last.to_sym
    end

    def body
      Settings[:iconmap][name]
    end

    def out_of_bounds?
      !x.between?(0, game.width) || !y.between?(0, game.height)
    end

    def initialize(game, coordinates)
      @game, @x, @y, = game, *coordinates
    end
  end

  class Rock < Entity

    def initialize(game, coordinates = game.random)
      super(game, coordinates)
    end
  end

  class Dirt < Entity

    def initialize(game, coordinates = game.random)
      super(game, coordinates)
    end
  end

  class Warpgate < Entity

    def full_power?
      if @power
        if @power > 20 #
          true         #
        else           # this sucks
          @power += 1  # refactor me
          false        #
        end            #
      else             #
        @power = 0     #
        false
      end
    end

    def activate
      case rand(3)
      when 0 then game.spawn(:rock, x, y) and kill
      when 1 then game.spawn(:alien, x, y) and kill
      when 2 then game.spawn(:alien, x, y) and kill
      end
    end

    def initialize(game, coordinates = game.random)
      super(game, coordinates)
    end
  end

  class Alien < Entity

    def kill
      Settings[:score] += 1 and super
    end

    def spawn
      game.spawn(:warpgate, x, y) if rand < Settings[:warps]
    end

    def move
      send %w(up down left right).sample
    end

    def initialize(game, coordinates = game.random)
      super(game, coordinates)
    end
  end

  class Dozer < Entity

    def initialize(game)
      super(game, game.center)
    end
  end
end

begin

  SpaceDozer::Game.new do |game|
    Signal.trap('INT') { game.stop }

    game.start

    # print the scoreboard when the game ends
    Curses.setpos(0, 0)                        #
    Curses.lines.times { Curses.deleteln }     #
                                               # refactor all of this mess
    time = (Time.now - Settings[:start]).to_i  #
    scoreboard = """You have died.

+ #{Settings[:score]} killed (x 40)
- #{time} seconds (x 1)

Score: #{Settings[:score] * 40 - time}"""

    scoreboard.lines.each_with_index do |line, index|
      x = Curses.lines - scoreboard.lines.count #
      y = Curses.cols - line.length             # this mess too
      Curses.setpos((x / 2) + index, y / 2)     #
      Curses.addstr line                        #
    end

    Curses.refresh
    Curses.close_screen
  end

rescue Exception => error
  Curses.close_screen

  puts error.message, *error.backtrace
end


