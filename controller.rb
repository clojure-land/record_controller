require 'pathname'
require 'fileutils'
require_relative 'spawn'

module RecordController
  class Controller
    include RecordController::Spawn

    attr_accessor :record_video, :record_audio, :playback_audio, :playback_video, :counter, :state

    DEBUG = false

    FFMPEG = %W[ffmpeg -an -f x11grab -r 25 -s 1280x720]
    CODEC  = %W[-vcodec libx264 -threads 3 -strict experimental -preset slow -crf 1 -pix_fmt yuv420p -qp 0]

    VIDEO_CMD =  FFMPEG + %W[-i :0.0] + CODEC
    VIDEO_CMD2 =  FFMPEG + %W[-i :2] + CODEC
    VIDEO_CMD3 =  FFMPEG + %W[-i :3] + CODEC

    AUDIO_CMD = %w[jack_capture --channels 1 --port system:capture_1]
    SCREENSHOT_CMD = "/home/arne/LambdaIsland/bin/screenshot"

    ALSA_IN_DEVICE="hw:Mic" #"hw:S6USB20"

    DIR = Pathname(__FILE__).dirname.expand_path

    TARGET_DIR_PATTERN = "/home/arne/LambdaIsland/Episodes/%s/rec"
    TARGET_TRASH_PATTERN = "/home/arne/LambdaIsland/Episodes/%s/.recTrash"

    def initialize(title)
      @title = title
      @now_playing = []
      @last_recordings = []
      @state = :stopped
      @blink = true
      @record_audio = true
      @record_video = false
      @playback_audio = true
      @playback_video = false
      set_counter!(last_sequence_number.next)
    end


    def running?(pid)
      begin
        Process.waitpid(pid, Process::WNOHANG) ? nil : true
      rescue Errno::ECHILD
      end
    end

    def output_dir
      dir = Pathname(TARGET_DIR_PATTERN % @title)
      dir.mkpath
      dir
    end

    def trash_dir
      dir = Pathname(TARGET_TRASH_PATTERN % @title)
      dir.mkpath
      dir
    end

    def set_counter!(c)
      @counter = c
    end

    def last_sequence_number
      output_dir.entries.map(&:to_s).map {|x| x[/^\d+/]}.compact.sort.last.to_i
    end

    def format_prefix(num)
      timestamp = `date +%Y%m%d-%H%M%S`.strip

      "%03d-%%s-#{timestamp}-#{@title}" % num
    end

    def spawn_video(vfile)
      spawn(*VIDEO_CMD, vfile)
    end

    def spawn_audio(afile)
      spawn(*AUDIO_CMD, afile)
    end

    def prepare_video!
      emacsclient("(plexus/screencast-mode)")
      emacsclient("(set-mouse-absolute-pixel-position 1277 720)")
    end

    def start!
      @did_commit = false
      @state = :recording
      p "starting"

      @pids = []

      prefix = format_prefix @counter
      fname = output_dir.join(prefix).to_s

      if @record_video
        prepare_video!
        vfile = "#{fname % 'V'}.mp4"
        pid_video, _ = spawn_video(vfile)
        @pids << pid_video
        @last_recordings.push(vfile)
      end

      # if @record_video
      #   vfile = "#{fname}--video2.mp4"
      #   pid_video, _ = spawn(*VIDEO_CMD3, vfile)
      #   @pids << pid_video
      #   @last_recordings.push(vfile)
      # end

      if @record_audio
        afile = "#{fname % 'A'}.wav"
        pid_audio, _ = spawn_audio(afile)
        @pids << pid_audio
        @last_recordings.push(afile)
      end

      @pids
    end

    def split_scenes(file)
      {}.tap do |res|
        current = ''
        file.each_line do |l|
          if l =~ /<!-- (.*) -->/
            current = ''
            res[$1.to_i] = current
          else
            current << l
          end
        end
      end
    end

    def stop!
      @pids.each {|pid|
        Process.kill("TERM", pid)
      }
      @pids = []
      @state = :stopped
    end

    def screenshot!
      prepare_video!
      prefix = format_prefix @counter
      fname = output_dir.join(prefix).to_s
      capture_screenshot!("#{fname % 'S'}.mp4")
    end

    def capture_screenshot!(sfile)
      spawn(SCREENSHOT_CMD, sfile)
      @last_recordings.push(sfile)
    end

    def current_counter_files
      Dir["#{output_dir}/#{"%03d" % @counter}*"]
    end

    def undo_record!
      begin
        f = @last_recordings.pop
        if f
          puts "Undo #{f}"
          FileUtils.mv(f, "#{trash_dir}/#{File.basename(f)}")
        else
          puts "No more undo history."
        end
      rescue => e
        puts e
      end
    end

    def pause!
      @pids.each do |p|
        Process.kill("STOP", p)
      end
    end

    def continue!
      @pids.each do |p|
        Process.kill("CONT", p)
      end
    end

    at_exit {
      if @jack_pid
        Process.kill("TERM", @jack_pid)
      end
    }

    def stopped?
      @state == :stopped
    end

    def recording?
      @state == :recording
    end

    def finishing?
      @state == :finishing
    end

    def paused?
      @state == :paused
    end

    # def update_leds!
    #   case @state
    #   when :stopped
    #     led! L_CUE, false
    #     led! L_PLAY, false
    #   when :paused
    #     led! L_CUE, false
    #     led! L_PLAY, @blink
    #   when :recording
    #     led! L_CUE, false
    #     led! L_PLAY, true
    #   when :finishing
    #     led! L_CUE, @blink
    #     led! L_PLAY, @blink
    #   end
    #   led! L_SYNC, @record_video
    #   led! L_PFL, @record_audio
    #   led! R_SYNC, @playback_video
    #   led! R_PFL, @playback_audio
    #   led! R_PLAY, @now_playing.any? {|pid| running?(pid) }
    # end

    def check_redshift
      unless `ps ax|grep redshift|grep -v grep`.empty?
        puts "Seems redshift is running, do you want to continue? [Y/n]"
        begin
          system("stty raw -echo")
          str = STDIN.getc
        ensure
          system("stty -raw echo")
        end
        exit -1 if str == "n"
        puts "ok"
      end
    end

    def check_jack
      if `ps ax|grep jackd|grep -v grep`.empty?
        puts "Seems jackd isn't running, start it now? [Y/n]"
        begin
          system("stty raw -echo")
          str = STDIN.getc
        ensure
          system("stty -raw echo")
        end
        if str != "n"
          @jack_pid = spawn("/usr/bin/pasuspender", "--", "/usr/bin/jackd", "-dalsa", "-d#{ALSA_IN_DEVICE}", "-r44100", "-p256", "-n2")
        end
      end
    end

    def record_controller_main
      loop do
        @now_playing.compact!
        sleep 0.7
      end
    end

    ############################################################
    # handlers

    def update_counter!(offset)
      set_counter!(@counter + offset)
    end

    def do_record
      if stopped?
        start!
        @state = :recording
      end
    end

    def do_stop
      if recording?
        stop!
        @state = :stopped
      elsif stopped?
        undo_record!
      end
    end

    def toggle_video
      @record_video = !@record_video
    end

    def toggle_audio
      @record_audio = !@record_audio
    end

    def toggle_playback_video
      @playback_video = !@playback_video
    end

    def toggle_playback_audio
      @playback_audio = !@playback_audio
    end

    def do_playback
      if @playback_video
        @now_playing.concat(current_counter_files.grep(/mp4/).map.with_index do |f, idx|
                              title = "mplayer-#{idx}"
                              spawn("mplayer", "-title", title, "-ao", "jack", f)
                            end)
      end
      if @playback_audio
        audio_files = current_counter_files.reject {|f| f =~ /mp4/}
        @now_playing << spawn("mplayer", "-ao", "jack", *audio_files)
      end
      sleep(0.2)
      current_counter_files.grep(/mp4/).map.with_index do |f, idx|
        title = "mplayer-#{idx}"
        spawn("wmctrl", "-r", title, "-e", "0,#{idx*1280},0,-1,-1")
      end
    end

    def do_stop_playback
      @now_playing.each do |pid|
        begin
          Process.kill("TERM", pid)
        rescue => e
        end
      end
      @now_playing = []
    end

    def do_screenshot
      screenshot!
    end
  end
end
