module Metanorma
  module Util
    class WorkersPool
      def initialize(workers)
        init_vars(workers)
        @threads = Array.new(@workers) do
          init_thread
        end
      end

      def init_vars(workers)
        @workers = workers
        @queue = SizedQueue.new(@workers)
        @mutex = Mutex.new
        @exceptions = []
      end

      def init_thread
        Thread.new do
          catch(:exit) do
            loop do
              job, args = @queue.pop
              run_job job, args
            end
          end
        end
      end

      # A job that raises must not take its worker thread down: the
      # thread stays in the loop, so jobs scheduled behind the failure
      # still run, and the exception is held for shutdown to re-raise
      # in the calling thread (#601). A dead worker here would deadlock
      # shutdown on a saturated queue and strand the remaining jobs.
      def run_job(job, args)
        job.call *args
      rescue StandardError => e
        @mutex.synchronize { @exceptions << e }
      end

      def schedule(*args, &block)
        @queue << [block, args]
      end

      # Drain the queue, join every worker, then propagate the first
      # job exception to the caller: a raising job must fail the run
      # that scheduled it, never exit 0.
      def shutdown
        @workers.times do
          schedule { throw :exit }
        end
        @threads.map(&:join)
        return if @exceptions.empty?

        raise @exceptions.first
      end
    end
  end
end
