# frozen_string_literal: true

module Metanorma
  class Compile
    # Opt-in per-phase wall-clock timing of a compile run, switched on by
    # the METANORMA_PROFILE environment variable or the :profile option.
    # Each phase prints one line to stdout when it ends; #report adds the
    # total. Asking for profiling is the opt-in, so the lines bypass the
    # Metanorma.configuration.logs filter (which excludes :info by
    # default). Disabled, #time just yields.
    class PhaseTimer
      OFF_VALUES = ["", "0", "false", "no", "off"].freeze

      def self.enabled?(options = {})
        options[:profile].nil? or return !!options[:profile]
        !OFF_VALUES.include?(ENV["METANORMA_PROFILE"].to_s.strip.downcase)
      end

      def initialize(enabled)
        @enabled = enabled
        @start = now
        @lock = Mutex.new
      end

      def enabled?
        @enabled
      end

      # Run the block, logging its duration as phase +name+. Safe to call
      # from WorkersPool threads.
      def time(name)
        @enabled or return yield
        t0 = now
        begin
          yield
        ensure
          log("[metanorma] Timing: #{name}: #{format_secs(now - t0)}")
        end
      end

      # Log the time elapsed since the timer was created
      def report
        @enabled or return
        log("[metanorma] Timing: total: #{format_secs(now - @start)}")
      end

      private

      def log(msg)
        @lock.synchronize { $stdout.puts(msg) }
      end

      def now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def format_secs(secs)
        format("%.3fs", secs)
      end
    end
  end
end
