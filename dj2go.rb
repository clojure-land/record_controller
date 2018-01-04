require 'wisper'

# DJ2Go midi specs
# https://www.klangfarbe.com/pdf/T//A-T40122_2.pdf

class DJ2Go
  ## Byte 0
  NOTE_ON  = 0x80
  NOTE_OFF = 0x90
  CONTROL  = 0xB0

  ## Byte 1
  L_CUE = 0x33
  L_PLAY = 0x3B
  L_SYNC = 0x40
  L_PFL = 0x65
  L_WHEEL = 0x19

  L_PITCH_MIN = 0x44
  L_PITCH_PLUS = 0x43

  R_CUE = 0x3C
  R_PLAY = 0x42
  R_SYNC = 0x47
  R_PFL = 0x66
  R_WHEEL = 0x18

  R_PITCH_MIN = 0x46
  R_PITCH_PLUS = 0x45

  BROWSE = 0x1A

  LEDS = [
    L_CUE,
    L_PLAY,
    L_SYNC,
    L_PFL,
    R_CUE,
    R_PLAY,
    R_SYNC,
    R_PFL,
  ]

  def initialize
    require 'unimidi'
    @in  = UniMIDI::Input.all.detect {|o| o.name =~ /DJ2Go/}
    @out = UniMIDI::Output.all.detect {|o| o.name =~ /DJ2Go/}

    @in_id = @in && @in.send(:instance_variable_get, '@device').system_id
    @in_raw = @in_id && AlsaRawMIDI::API::Input.open(@in_id)

    if @out
      @out.open
    else
      raise "DJ2Go not found"
    end

    at_exit do
      if @out
        LEDS.each {|l| led! l, false }
      end
    end
  end

  def run!
    Thread.new do
      loop do
        begin
          res = AlsaRawMIDI::API::Input.poll(@in_raw)
          handle(*res.scan(/../).map(&:hex)) if res
          sleep 0.1
        rescue => e
          puts "Exception in MIDI Thread: #{e}"
          puts e.backtrace
        end
      end
    end
  end

  def handle(a, b, c)
    broadcast(:MIDI, a, b, c)
    begin
      case a
      when CONTROL
        case b
        when BROWSE
          c = c - 128 if c >= 64
          broadcast(:control_browse, c)
        end
      when NOTE_ON
        case b
        when L_PLAY
          broadcast(:NOTE_ON_L_PLAY)
        when L_CUE
          broadcast(:NOTE_ON_L_CUE)
        when L_SYNC
          broadcat(:NOTE_ON_L_SYNC)
        when L_PFL
          broadcast(:NOTE_ON_L_PFL)
        when R_SYNC
          broadcast(:NOTE_ON_R_SYNC)
        when R_PFL
          broadcast(:NOTE_ON_R_PFL)
        when R_PLAY
          broadcast(:NOTE_ON_R_PLAY)
        when R_CUE
          broadcast(:NOTE_ON_R_CUE)
        end
      when NOTE_OFF
        case b
        when L_PITCH_PLUS
          broadcast(:NOTE_OFF_L_PITCH_PLUS)
        end
      end
    end
  end

  def led!(led, on)
    @out.puts(0x90, led, on ? 1 : 0)
  end
end
