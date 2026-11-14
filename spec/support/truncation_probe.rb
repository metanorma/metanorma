# frozen_string_literal: true

# TRUNCATION-PROBE for metanorma#706.
#
# Symptom: on GHA, `rake` (rspec) terminates MID-SUITE with exit 1 and
# 0 failures (e.g. after 46 of 202 examples) on every OS/Ruby leg,
# reproducible on rerun, while the same suite is green locally. The
# truncation is silent: no failure summary, just an early stop.
#
# This probe names whatever ends the process:
#
# * Kernel#exit / Kernel#exit! / Kernel#abort are wrapped with
#   prepended modules (both the bare/object-context forms and the
#   Kernel.exit singleton form), plus Process.exit / Process.exit!.
#   Each invocation is logged to STDERR with its arguments, ARGV, the
#   exception in flight ($!), and the full caller stack BEFORE the
#   original method runs, so a silent exit from inside a passing spec
#   or a gem names its caller. Kernel#exit! bypasses at_exit hooks
#   entirely, so the wrapper is its only witness.
# * An at_exit hook reports the terminating status and exception per
#   the classic contract ($! holds the terminating exception inside
#   at_exit; `raise $! if $!` re-raises so the exit status is
#   preserved), including the exception backtrace.
# * An RSpec after(:suite) hook prints the example count; its absence
#   in the log means the suite never finished.
#
# Reading a truncated CI log:
# * "called with" marker + caller = the culprit (or a deliberate exit).
# * "at_exit fired ... exception=<X>" with a backtrace = uncaught
#   exception that RSpec did not handle.
# * No markers at all and no "suite completed normally" line = the
#   process was killed by a signal (OOM SIGKILL, CI runner shutdown),
#   which Ruby cannot intercept.
#
# ENABLEMENT (CI): the rake job delegates to the reusable workflow
# metanorma/ci/.github/workflows/generic-rake.yml@main whose test step
# is a bare `bundle exec rake`, so inject the env at the workflow level
# of .github/workflows/rake.yml (caller workflow-level env propagates
# into the called reusable workflow's steps). After the `permissions:`
# block, add:
#
#   env:
#     MN_TRUNCATION_PROBE: "1"
#
# Remove the block once #706 is diagnosed. Without the env var no
# hooks are installed and normal runs are untouched.
module Metanorma
  # CI-truncation diagnostic probe (metanorma#706); installs exit
  # tracing only when MN_TRUNCATION_PROBE=1.
  module TruncationProbe
    MARKER = "TRUNCATION-PROBE:"

    # Intercepts bare/object-context exit calls (`exit 1`, `abort "x"`)
    # in any object whose class includes Kernel -- i.e. every object.
    module KernelExitWrapper
      def exit(*args)
        TruncationProbe.trace_exit("Kernel#exit", args)
        super
      end

      def exit!(*args)
        TruncationProbe.trace_exit("Kernel#exit!", args)
        super
      end

      def abort(*args)
        TruncationProbe.trace_exit("Kernel#abort", args)
        super
      end
    end

    # Intercepts explicit `Kernel.exit`/`Kernel.exit!` singleton calls.
    module KernelSingletonExitWrapper
      def exit(*args)
        TruncationProbe.trace_exit("Kernel.exit", args)
        super
      end

      def exit!(*args)
        TruncationProbe.trace_exit("Kernel.exit!", args)
        super
      end
    end

    # Intercepts explicit `Process.exit`/`Process.exit!` calls.
    module ProcessExitWrapper
      def exit(*args)
        TruncationProbe.trace_exit("Process.exit", args)
        super
      end

      def exit!(*args)
        TruncationProbe.trace_exit("Process.exit!", args)
        super
      end
    end

    def self.enabled?
      ENV["MN_TRUNCATION_PROBE"] == "1"
    end

    def self.install!
      return if @installed

      Kernel.prepend(KernelExitWrapper)
      Kernel.singleton_class.prepend(KernelSingletonExitWrapper)
      Process.singleton_class.prepend(ProcessExitWrapper)
      register_exit_reporter
      @installed = true
      log("probe installed, pid=#{Process.pid}, ARGV=#{ARGV.inspect}")
    end

    # Hooked from spec/spec_helper.rb's RSpec.configure block; no-op
    # unless the probe is enabled.
    def self.configure_rspec(config)
      return unless enabled?

      config.fail_fast = false
      config.after(:suite) { Metanorma::TruncationProbe.log_suite_completion }
    end

    def self.trace_exit(label, args)
      @requested_status = derive_status(args)
      log("#{label} called with #{args.inspect}, " \
          "ARGV=#{ARGV.inspect}, $!=#{$!.inspect}")
      caller.each { |frame| log("  from #{frame}") }
    end

    def self.log(message)
      warn("#{MARKER} #{message}")
    end

    def self.register_exit_reporter
      at_exit do
        err = $!
        status = terminating_status(err)
        log("at_exit fired, exit status=#{status.inspect}, " \
            "exception=#{describe_exception(err)}")
        Array(err&.backtrace).each { |frame| log("  at #{frame}") }
        raise err if err
      end
    end

    # The classic at_exit contract: $! holds the terminating exception.
    # SystemExit carries its own status; an uncaught non-SystemExit
    # exception terminates with 1; with nothing in flight the process
    # is finishing normally (0) unless a wrapped exit call recorded one.
    def self.terminating_status(err)
      return err.status if err.is_a?(SystemExit)
      return 1 if err

      @requested_status || 0
    end

    def self.log_suite_completion
      # Count examples that actually finished, not just declared ones:
      # on a normal exit the two coincide, and after a mid-suite
      # SystemExit the gap is itself diagnostic.
      count = RSpec.world.all_example_groups.sum do |group|
        group.examples.count { |example| example.execution_result.finished_at }
      end
      log("suite completed normally with #{count} examples")
    end

    def self.describe_exception(err)
      return "none" unless err

      "#{err.class}: #{err.message}"
    end

    # Best-effort mirror of Kernel#exit's status semantics (true -> 0,
    # integer -> itself, anything else -> 1); the authoritative status
    # is SystemExit#status reported by the at_exit hook.
    def self.derive_status(args)
      status = args.first
      return status if status.is_a?(Integer)
      return 0 if status.equal?(true)

      1
    end
  end
end

Metanorma::TruncationProbe.install! if Metanorma::TruncationProbe.enabled?
