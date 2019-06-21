require 'wisper'

# Wrapper for the ShuttleXpress HID device
# Call run! to start the event loop. Broadcasts wisper events:
#
#   - button_down_n / button_up_n
#   - wheel
#   - jog
#
# The wheel and jog event receive both a relative difference (-1 or 1), and the
# absolute position (for wheel: 0 to 255, for jog: -7 to 7)
module RecordController
  class ShuttleXpress
    include Wisper::Publisher
    attr_reader :device, :last_event

    HID_VENDOR_ID = 0x0b33
    HID_PRODUCT_ID = 0x0020

    def initialize
      require 'hidapi'
      @device = HIDAPI::open(HID_VENDOR_ID, HID_PRODUCT_ID)
      @last_event = [0, nil, 0, 0, 0]
    end

    def run!
      @stopped = false
      Thread.new do
        loop do
          print "."
          input = device.read
          break if input.nil?
          begin
            handle!(input.unpack('C*'))
            break if @stopped
          rescue => e
            p e
            puts e.backtrace
          end
        end
      end
    end

    def stop!
      @stopped = true
    end

    def handle!(event)
      jog, wheel, _, bitmask1, bitmask2 = event
      old_jog, old_wheel, _, old_bitmask1, old_bitmask2 = last_event

      old_wheel = wheel if old_wheel.nil?

      button_states(old_bitmask1, old_bitmask2).zip(button_states(bitmask1, bitmask2)).each.with_index do |(old, new), idx|
        if old == false && new == true
          broadcast(:"button_down_#{idx+1}")
        elsif old == true && new == false
          broadcast(:"button_up_#{idx+1}")
        end
      end

      if (wheel-old_wheel) > 1
        broadcast(:wheel, wheel - 256 - old_wheel, wheel)
      elsif (wheel-old_wheel) < -1
        broadcast(:wheel, wheel + 256 - old_wheel, wheel)
      else
        broadcast(:wheel, wheel - old_wheel, wheel)
      end

      jog = jog - 256 if jog > 200
      old_jog = old_jog - 256 if old_jog > 200

      if jog > old_jog
        broadcast(:jog, jog - old_jog, jog)
      elsif jog < old_jog
        broadcast(:jog, old_jog - jog, jog)
      end

      @last_event = event
    end

    def button_states(bitmask1, bitmask2)
      [
        bitmask1[4],
        bitmask1[5],
        bitmask1[6],
        bitmask1[7],
        bitmask2[0]
      ].map {|i| i == 1}
    end
  end
end

__END__

shuttle = ShuttleXpress.new
shuttle.run!

shuttle.on(:button_down_1) { p "yoooow"}
shuttle.on(:wheel_left) {|rel, abs| p "wheel_left rel=#{rel} abs=#{abs}"}
shuttle.on(:wheel_right) {|rel, abs| p "wheel_right rel=#{rel} abs=#{abs}"}
shuttle.on(:jog_left) {|rel, abs| p "jog_left rel=#{rel} abs=#{abs}"}
shuttle.on(:jog_right) {|rel, abs| p "jog_right rel=#{rel} abs=#{abs}"}
