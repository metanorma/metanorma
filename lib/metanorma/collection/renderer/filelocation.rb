# frozen_string_literal: true

module Metanorma
  class Collection
    class Renderer
      def file_compile_formats(filename, identifier, opts)
        f = @files.get(identifier, :outputs)
        format = opts[:extension_keys]
        concatenate_presentation?({ format: }) and format << :presentation
        format.each do |e|
          e == :pdf and output_filename = opts[:pdffile]
          file_compile_format(filename, identifier, e, f, output_filename)
        end
        @files.set(identifier, :outputs, f)
      end

      # if new_output_fname is present, move generated file for format
      # to the nominated new file name
      def file_compile_format(fname, ident, format, outputs, new_output_fname)
        ext = @compile.processor.output_formats[format]
        fname_base = File.basename(fname)
        # ONLY replace .xml or .html extensions, NEVER remove section numbers like .0
        output_fname = if /\.(xml|html)$/.match?(fname_base)
                         fname_base.sub(/\.(xml|html)$/, ".#{ext}")
                       else
                         "#{fname_base}.#{ext}"
                       end

        if new_output_fname
          FileUtils.mv(File.join(@outdir, output_fname),
                       File.join(@outdir, new_output_fname))
          output_fname = new_output_fname
        elsif (custom_fname = @files.preserve_directory_structure?(ident))
          # Get the custom directory structure from the file metadata
          # Substitute placeholders like {document-num}
          idx = @files.get(ident, :idx)
          # Get basename from the ORIGINAL source file, not the renamed output
          original_file = @files.get(ident, :ref)
          basename = File.basename(original_file, ".*")
          basename_legacy = File.basename(original_file)
          custom_fname = @files.substitute_filename_pattern(
            custom_fname,
            document_num: idx,
            basename: basename,
            basename_legacy: basename_legacy,
          )
          fname_dir = File.dirname(custom_fname)
          if fname_dir != "."
            # Don't add directory here - let preserve_output_dir_structure handle it
            # to avoid double-adding the directory path
            # Pass explicit_custom flag to indicate this is from output-filename
            output_fname = preserve_output_dir_structure(custom_fname, output_fname,
                                                         format, explicit_custom: true)
          end
        elsif File.dirname(fname) != "."
          # Preserve directory structure if fname itself contains a directory
          fname_dir = File.dirname(fname)
          output_fname = File.join(fname_dir, output_fname)
          output_fname = preserve_output_dir_structure(fname, output_fname,
                                                       format)
        end
        should_skip = /html$/.match?(ext) && @files.get(ident, :sectionsplit)
        should_skip or outputs[format] = File.join(@outdir, output_fname)
      end

      # Preserve directory structure from input filename in output
      # Move HTML, DOC, PDF to subdirectories when explicit output-filename is set
      # XML and presentation.xml stay in root directory (default behavior)
      # @param fname [String] input filename (may include directory)
      # @param output_fname [String] output filename (may already include directory)
      # @param format [Symbol] output format (:html, :presentation, etc.)
      # @param explicit_custom [Boolean] true if this is from an explicit output-filename directive
      def preserve_output_dir_structure(fname, output_fname, format = nil,
explicit_custom: false)
        fname_dir = File.dirname(fname)
        if fname_dir != "."
          # output_fname might already include the directory, so get just the basename for source
          output_basename = File.basename(output_fname)
          # Determine if we should move based on format extension
          ext = format ? @compile.processor.output_formats[format].to_s : ""
          # If explicit_custom (from output-filename), move HTML, DOC, PDF, presentation.xml (but not regular XML)
          # Otherwise, only move HTML/presentation files (default behavior)
          should_move = if explicit_custom
                          # For explicit output-filename: move html, doc, pdf, presentation.xml (not regular xml)
                          ext.end_with?("html") || ext == "doc" || ext == "pdf" ||
                            output_basename.end_with?(".presentation.xml")
                        else
                          # Default behavior: only HTML and presentation
                          ext.end_with?("html") || output_basename.end_with?(
                            ".html", ".presentation.xml"
                          )
                        end
          if should_move
            output_with_dir = File.join(fname_dir, output_basename)
            output_dest = File.join(@outdir, output_with_dir)
            output_src = File.join(@outdir, output_basename)
            if File.exist?(output_src) && output_src != output_dest
              FileUtils.mkdir_p(File.dirname(output_dest))
              FileUtils.mv(output_src, output_dest)
              # Note: .err.html files are left in the root directory intentionally
              # They are not moved to subdirectories with their parent HTML files
              return output_with_dir
            elsif File.exist?(output_dest)
              # File already exists at destination (from a previous call)
              # Return the correct path with directory
              if File.exist?(output_src)
                # Source still exists, clean it up
                FileUtils.rm_f(output_src)
                err_src = output_src.sub(/\.html$/, ".err.html")
                FileUtils.rm_f(err_src) if File.exist?(err_src)
              end
              return output_with_dir
            end
          elsif explicit_custom
            # File was not moved - return just the basename since it's in root directory
            # For explicit_custom with output-filename, use the custom basename + extension
            custom_basename = File.basename(fname, ".*")
            ext = File.extname(output_basename)
            return "#{custom_basename}#{ext}"
          else
            return output_basename
          end
        end
        output_fname
      end

      def copy_file_to_dest(identifier)
        out = Pathname.new(@files.get(identifier, :out_path)).cleanpath
        out.absolute? and
          out = out.relative_path_from(File.expand_path(FileUtils.pwd))
        dest = File.join(@outdir, @disambig.source2dest_filename(out.to_s))
        FileUtils.mkdir_p(File.dirname(dest))
        source = @files.get(identifier, :ref)
        source != dest and FileUtils.cp_r source, dest, remove_destination: true
      end
    end
  end
end
