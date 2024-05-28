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
      end

      def init_thread
        Thread.new do
          catch(:exit) do
            loop do
              job, args = @queue.pop
              job.call *args
            end
          end
        end
      end

      def schedule(*args, &block)
        @queue << [block, args]
      end

      def shutdown
        @workers.times do
          schedule { throw :exit }
        end
        @threads.map(&:join)
      end
    end
  end
end
