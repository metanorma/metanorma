require_relative "../../spec_helper"

RSpec.describe Metanorma::Util::WorkersPool do
  # A job that raises must fail the pool loudly: shutdown re-raises the
  # exception in the calling thread (#601), and the worker that hit the
  # failure keeps serving the jobs scheduled behind it, so one failed
  # job never silently drops the rest of the queue.
  it "re-raises a raising job at shutdown, and jobs behind it still run" do
    done_file = "worker_pool_spec_later.txt"
    pool = described_class.new(1)
    pool.schedule { raise Errno::ENOENT, "posix_spawn /bin/sh" }
    pool.schedule { File.write(done_file, "ran") }

    expect { pool.shutdown }.to raise_error(Errno::ENOENT, /posix_spawn/)
    expect(File.read(done_file)).to eq("ran")
  ensure
    FileUtils.rm_f(done_file)
  end
end
