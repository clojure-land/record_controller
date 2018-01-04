module RecordController
  module Spawn
    def spawn(*args)
      puts args.join(" ")
      if IO.respond_to? :popen4
        IO.popen4(*args)
      else
        Process.spawn(*args) # used on 1.9
      end
    end

    def emacsclient(*args)
      spawn('/usr/local/bin/emacsclient', '-e', *args)
    end

  end
end
