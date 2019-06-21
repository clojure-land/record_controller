# TODO this is terrible, seems popen4 isn't that widely available, and the
# return types are completely different (id, in, out, err) vs just (id)

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
      spawn('/usr/local/bin/emacsclient',
            #'-s', '/tmp/arne/emacs1000/server',
            '-e', *args)
    end

    def running?(pid)
      `kill -0 #{pid} 2>/dev/null ; echo $?`.strip == "0"
    end

  end
end
