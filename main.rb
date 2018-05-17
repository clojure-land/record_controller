#!/usr/bin/env ruby

require_relative 'controller'
require_relative 'shuttle_xpress'
require_relative 'spawn'

@title = ARGV.shift

unless @title
  STDERR.puts "Please provide a title"
  exit -1
end

@controller = RecordController::Controller.new(@title)

@controller.check_redshift
@controller.check_jack

@shuttlexpress = RecordController::ShuttleXpress.new

class ShuttleAdapter
  include RecordController::Spawn

  attr_reader :controller

  def initialize(controller)
    @controller = controller
    update_emacs!
  end

  # Toggle A/V  |  Stop/Undo  |  Record  | Screenshot  |  Playback

  def setq(var, val)
    val = case val
          when NilClass
            "nil"
          when FalseClass
            "nil"
          when TrueClass
            "t"
          when String
            val.inspect
          when Symbol
            "'#{val.to_s}"
          else
            val
          end
    emacsclient("(setq #{var} #{val})")
  end

  def button_down_2
    if controller.record_audio && !controller.record_video
      controller.record_audio = false
      controller.record_video = true
      controller.playback_audio = false
      controller.playback_video = true
    elsif !controller.record_audio && controller.record_video
      controller.record_audio = true
      controller.record_video = true
      controller.playback_audio = true
      controller.playback_video = true
    else
      controller.record_audio = true
      controller.record_video = false
      controller.playback_audio = true
      controller.playback_video = false
    end

    update_emacs!
  end

  def button_down_1
    if controller.recording?
      controller.stop!
    elsif controller.stopped?
      controller.undo_record!
    end
    update_emacs!
  end

  def button_down_3
    if controller.stopped?
      controller.start!
    end
    update_emacs!
  end

  def button_down_4
    controller.do_screenshot
  end

  def button_down_5
    controller.do_playback
    update_emacs!
  end

  def wheel(offset, abs)
    controller.update_counter!(offset)
    update_emacs!
  end

  def update_emacs!
    emacsclient("(plexus/set-record-counter #{controller.counter})")
    setq("plexus/record-video", controller.record_video)
    setq("plexus/record-audio", controller.record_audio)
    setq("plexus/record-clipped", controller.clipped)
    setq("plexus/record-state", controller.state)
  end
end

@shuttlexpress.subscribe(ShuttleAdapter.new(@controller))

@shuttlexpress.run!.join
