# frozen_string_literal: true

require "open3"
require "pathname"
require "set"

module Metanorma
  class Collection
    # The files of a collection's git repository that changed since a git
    # ref, for change-aware collection builds (metanorma-cli#495): a
    # member whose sources did not change keeps its existing output
    # instead of being compiled again.
    #
    # The comparison is between REF and the working tree, so committed,
    # staged and unstaged edits all count, as do untracked files. A
    # member's sources are its file, the AsciiDoc file it is compiled from
    # (for an XML member with an .adoc sibling), and everything those
    # include, transitively. Include targets built from attribute
    # references cannot be resolved without compiling, so they are not
    # followed.
    class ChangeSet
      INCLUDE = /^include::([^\[\n]+)\[/

      attr_reader :ref

      # A ChangeSet passes through; a git ref builds one; nil means a
      # normal build, which renders every member.
      def self.for(value, dir)
        case value
        when nil, false, "" then nil
        when ChangeSet then value
        else new(value.to_s, dir)
        end
      end

      def initialize(ref, dir)
        @ref = ref
        @dir = File.expand_path(dir)
        # The top level as a path relative to dir, resolved by Ruby like the
        # member paths, so both sides compare equal (Windows short names,
        # symlinked checkouts).
        cdup, ok = git("rev-parse", "--show-cdup")
        ok or raise ArgumentError, "#{@dir} is not inside a git repository"
        @root = norm(File.expand_path(cdup.strip, @dir))
        git("rev-parse", "--verify", "--quiet", "#{ref}^{commit}").last or
          raise ArgumentError, "unknown git ref #{ref} in #{@root}"
        @changed = changed_paths
        @memo = {}
        @mutex = Mutex.new
      end

      # Absolute paths of the files that changed since the ref.
      def paths
        @changed.dup
      end

      # Did the member stored at file change since the ref?
      def changed?(file)
        abs = norm(File.expand_path(file, @dir))
        @mutex.synchronize do
          @memo.fetch(abs) do
            @memo[abs] = sources(abs).any? { |s| @changed.include?(s) }
          end
        end
      end

      def sources(file)
        roots = [file]
        adoc = file.sub(/\.xml\z/, ".adoc")
        adoc != file && File.exist?(adoc) and roots << adoc
        roots.each_with_object(Set.new) { |r, seen| includes(r, seen) }
      end

      private

      def changed_paths
        diff, ok = git("diff", "--name-only", "-z", @ref, "--")
        ok or raise ArgumentError, "git diff against #{@ref} failed"
        untracked, = git("ls-files", "--others", "--exclude-standard", "-z")
        (diff.split("\0") + untracked.split("\0")).to_set do |p|
          File.join(@root, p)
        end
      end

      def includes(file, seen)
        seen.include?(file) and return seen
        seen << file
        file.end_with?(".adoc") && File.file?(file) or return seen
        File.read(file, encoding: "UTF-8").scan(INCLUDE).flatten.each do |t|
          t.include?("{") and next
          includes(norm(File.expand_path(t.strip, File.dirname(file))), seen)
        end
        seen
      end

      # Resolve symlinks the same way for the top level and member paths.
      def norm(path)
        File.exist?(path) ? File.realpath(path) : path
      end

      def git(*args)
        out, status = Open3.capture2("git", "-C", @dir, *args,
                                     err: File::NULL)
        [out, status.success?]
      end
    end
  end
end
