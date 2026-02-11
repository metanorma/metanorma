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

      # Generate output filename with correct extension
      def output_filename_with_extension(fname, format)
        ext = @compile.processor.output_formats[format]
        fname_base = File.basename(fname)
        # ONLY replace .xml or .html extensions, NEVER remove section numbers
        if /\.(xml|html)$/.match?(fname_base)
          fname_base.sub(/\.(xml|html)$/, ".#{ext}")
        else
          "#{fname_base}.#{ext}"
        end
      end

      # Move file to new output filename if specified
      def handle_new_output_filename(output_fname, new_output_fname)
        return output_fname unless new_output_fname

        FileUtils.mv(File.join(@outdir, output_fname),
                     File.join(@outdir, new_output_fname))
        new_output_fname
      end

      # Apply custom filename pattern with substitutions
      def apply_custom_filename_pattern(ident, custom_fname, output_fname,
format)
        idx = @files.get(ident, :idx)
        original_file = @files.get(ident, :ref)
        basename = File.basename(original_file, ".*")
        basename_legacy = File.basename(original_file)
        custom_fname = @files.substitute_filename_pattern(
          custom_fname, document_num: idx,
                        basename: basename, basename_legacy: basename_legacy
        )
        if File.dirname(custom_fname) == "."
          output_fname
        else
          preserve_output_dir_structure(custom_fname, output_fname,
                                        format, explicit_custom: true)
        end
      end

      # Apply directory preservation for files with directory structure
      def apply_directory_preservation(fname, output_fname, format)
        fname_dir = File.dirname(fname)
        output_fname = File.join(fname_dir, output_fname)
        preserve_output_dir_structure(fname, output_fname, format)
      end

      # Compile single format for a file and update outputs hash
      def file_compile_format(fname, ident, format, outputs, new_output_fname)
        ext = @compile.processor.output_formats[format]
        output_fname = output_filename_with_extension(fname, format)
        output_fname = handle_new_output_filename(output_fname,
                                                  new_output_fname)
        if !new_output_fname && (custom = @files.preserve_directory_structure?(ident))
          output_fname = apply_custom_filename_pattern(ident, custom,
                                                       output_fname, format)
        elsif !new_output_fname && File.dirname(fname) != "."
          output_fname = apply_directory_preservation(fname, output_fname,
                                                      format)
        end
        should_skip = /html$/.match?(ext) && @files.get(ident, :sectionsplit)
        should_skip or outputs[format] = File.join(@outdir, output_fname)
      end

      # Determine if file should be moved to subdirectory
      def should_move_to_subdirectory?(ext, output_basename, explicit_custom)
        if explicit_custom
          # For explicit output-filename: move html, doc, pdf, presentation.xml
          ext.end_with?("html") || ext == "doc" || ext == "pdf" ||
            output_basename.end_with?(".presentation.xml")
        else
          # Default: only HTML and presentation files
          ext.end_with?("html") ||
            output_basename.end_with?(".html", ".presentation.xml")
        end
      end

      # Move file from root to subdirectory
      def move_file_to_subdirectory(fname_dir, output_basename)
        output_with_dir = File.join(fname_dir, output_basename)
        output_dest = File.join(@outdir, output_with_dir)
        output_src = File.join(@outdir, output_basename)
        return nil unless File.exist?(output_src) && output_src != output_dest

        FileUtils.mkdir_p(File.dirname(output_dest))
        FileUtils.mv(output_src, output_dest)
        output_with_dir
      end

      # Handle case where destination already exists
      def handle_existing_destination(output_with_dir, output_src)
        output_dest = File.join(@outdir, output_with_dir)
        return nil unless File.exist?(output_dest)
        return output_with_dir unless File.exist?(output_src)

        FileUtils.rm_f(output_src)
        err_src = output_src.sub(/\.html$/, ".err.html")
        FileUtils.rm_f(err_src) if File.exist?(err_src)
        output_with_dir
      end

      # Generate custom basename with extension
      def custom_basename_with_extension(fname, output_basename)
        custom_basename = File.basename(fname, ".*")
        ext = File.extname(output_basename)
        "#{custom_basename}#{ext}"
      end

      # Preserve directory structure from input filename in output
      def preserve_output_dir_structure(fname, output_fname, format = nil,
explicit_custom: false)
        fname_dir = File.dirname(fname)
        return output_fname if fname_dir == "."

        output_basename = File.basename(output_fname)
        ext = format ? @compile.processor.output_formats[format].to_s : ""
        should_move = should_move_to_subdirectory?(ext, output_basename,
                                                   explicit_custom)
        if should_move
          result = move_file_to_subdirectory(fname_dir, output_basename)
          return result if result

          handle_existing_destination(File.join(fname_dir, output_basename),
                                      File.join(@outdir,
                                                output_basename)) || output_fname
        elsif explicit_custom
          custom_basename_with_extension(fname, output_basename)
        else
          output_basename
        end
      end

      def copy_file_to_dest(identifier)
        out = Pathname.new(@files.get(identifier, :out_path)).cleanpath
        out.absolute? and
          out = out.relative_path_from(File.expand_path(FileUtils.pwd))
        dest = File.join(@outdir,
                         @disambig.source2dest_filename(out.to_s,
                                                        preserve_dirs: true))
        FileUtils.mkdir_p(File.dirname(dest))
        source = @files.get(identifier, :ref)
        source != dest and FileUtils.cp_r source, dest, remove_destination: true
      end
    end
  end
end
