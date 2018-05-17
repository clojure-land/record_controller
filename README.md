This is the code I use to record Lambda Island episodes. It's a huge kludge of a
Ruby script that talks to a MIDI or HDI controller, lauches jackd, starts and
stops recordings, detects clipped audio, and communicates with Emacs to make the
whole process visible.

It's mostly shared for academic purposes, I would be thrilled and somewhat
horrified if anyone besides me could actually make use of this.
