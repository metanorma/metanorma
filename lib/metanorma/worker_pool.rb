module Metanorma
  class WorkersPool
    def initialize(workers)
      @workers = workers
      @queue = SizedQueue.new(@workers)
      @threads = Array.new(@workers) do
        Thread.new do
          catch(:exit) do
            loop do
              job, args = @queue.pop
              job.call *args
            end
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
