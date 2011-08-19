require 'find'
require 'pathname'
require 'erb'
require 'fileutils'

# TODO: test if necessary binaries are installed
# TODO: test if soxi compiled with LAME
# check and update metadata

module Lossfully
  class Generator

    def self.sort_by_rules array
      array.sort { |x,y| (x[0] <=> y[0]) rescue 0 }
    end

    def self.sort_by_rules! array
      array.sort! { |x,y| (x[0] <=> y[0]) rescue 0 }
    end

    def self.determine_rule array, file
      array.each do |r|
        if result = r[0].test(file)
          return (result == true) ? r[1] : result
        end
      end
      return nil
    end

    def initialize &block
      @encode_rules = Array.new
      @path_rules = Array.new
      @option_rules = Array.new
      @effect_option_rules = Array.new
      @clobber_rules = Array.new
      @remove_missing_rules = Array.new

      @verbosity = 1
      @threads = 1
      
      # set default rules for commands
      encode :everything => :copy
      path :everything => :original
      clobber :everything => true
      remove_missing :everything => true
      options :audio => ''
      effect_options :audio => ''

      if block_given?
        if block.arity == 1
          yield self
        else
          instance_eval(&block)
        end
      end 
    end
    
    attr_accessor :verbosity
    attr_writer :rel_path, :threads

    def threads arg=nil
      if arg
        @threads = arg
      end
      @threads
    end

    def rel_path arg=nil
      if arg
        @rel_path = File.directory?(arg) ? arg : File.dirname(arg)
      else
        rel_path $0
      end
    end

    def quiet bool=true
      @verbosity = bool ? 0 : 1
    end

    # Print + "\n" is used instead of puts because sometimes two puts
    # strings are printed together and then the newlines together.  I
    # guess because of threading.
    #
    def message str
      print str + "\n" unless @verbosity == 0
    end

    def generate *args
      if args.size == 1 then 
        hash = args[0]
        raise "Target not specified" unless hash.kind_of? Hash
        raise "Hash must have only one key-value pair." unless hash.size == 1
        primary = hash.keys.first
        target  = hash.values.first
      else
        raise "Input incorrectly specified." if args.size > 2
        primary = args[0]
        target  = args[1]
      end

      raise "Converting from multiple libraries is not supported" if primary.kind_of? Array
      raise "Writing to multiple directories is not supported" if target.kind_of? Array
      primary = File.expand_path primary, File.dirname(rel_path())
      target = File.expand_path target, File.dirname(rel_path())

      raise "Overwriting original library not supported." if primary == target

      [@encode_rules,
       @path_rules,
       @option_rules,
       @effect_option_rules,
       @clobber_rules,
       @remove_missing_rules].each do |a|
        self.class.sort_by_rules! a
      end

      encode_actions = ThreadPool.new(@threads) 
      copy_actions = ThreadPool.new(1) 

      int_level = 0
      trap("INT") do 
        if int_level == 0 
          int_level += 1
          message "\nWill stop after current processes are finished; press CTRL-C again to stop immediately."
          encode_actions.stop 
          copy_actions.stop 
          abort
        else
          encode_actions.kill
          copy_actions.kill
        end
      end

      files_to_keep = []

      if File.file? primary
        files = File.readlines(primary).map { |f| f.chomp }.uniq
        if File.extname(primary) == '.cue'
          file = files.select { |f| f =~ /^FILE/ }
          files.map! { |f| f.match(/"(.*[^\\])"/)[1] }
        end
        primary = File.dirname(primary)
        files.map! { |f| File.expand_path(f.strip, primary) }
        files = files.select { |f| File.file? f }
        files.uniq!
      else
        files = []
        Find.find(primary) { |file| files << file unless File.directory? file}
      end

      files.each_with_index do |file, file_index|
        next if File.directory? file
        
        file_index += 1
        file_rel_name = Pathname.new(file).relative_path_from(Pathname.new(primary))
        file_rel_name = File.basename(primary) + '/' + file_rel_name.to_s
        message "check [#{file_index}/#{files.size}] " + file_rel_name

        # By making `file' into an AudioFile we gain memoization,
        # which actually speeds things up quite a bit for some hard
        # drives.
        file = AudioFile.new(file)

        encoding = self.class.determine_rule @encode_rules, file
        encoding = Array(encoding) unless encoding.kind_of? Array

        next if encoding[0] == :skip
        path = determine_path file, primary, target, encoding
        files_to_keep << path

        if File.exist? path
          clobber = self.class.determine_rule @clobber_rules, file
          next unless clobber # if clobber == false
          if clobber.kind_of? String
            path = path.chomp(File.extname(path)) + clobber + File.extname(path)
            files_to_keep << path
          elsif clobber == :rename
            i = '1'
            begin
              new_path = path.chomp(File.extname(path)) + " (#{i.succ!})" + File.extname(path)
              files_to_keep << new_path
            end while File.exist? new_path
            path = new_path
          end
        end

        path_rel_name = Pathname.new(path).relative_path_from(Pathname.new(target))
        path_rel_name = File.basename(target) + '/' + path_rel_name.to_s
        # copy rather than reencoding if possible
        if encoding[0] == :copy || 
            (encoding[0] != :reencode && 
             (File.extname(path) == File.extname(file.path) && encoding[1].nil?))
          n = copy_actions.total + 1
          copy_actions << lambda do
            message "copy [#{n}/#{copy_actions.total}] " + path_rel_name
            FileUtils.mkdir_p File.dirname(path)
            FileUtils.cp(file.path, path) 
          end
        else
          options = self.class.determine_rule @option_rules, file
          effect_options = self.class.determine_rule @effect_option_rules, file
          n = encode_actions.total + 1
          encode_actions << lambda do
            message "encode [#{n}/#{encode_actions.total}] " + path_rel_name
            FileUtils.mkdir_p File.dirname(path)
            options = "-C #{encoding[1]} " + options if encoding[1].kind_of? Numeric
            file.encode path, options, effect_options 
          end
        end
      end

      encode_actions.join
      copy_actions.join

      files_to_keep.uniq!
      Find.find(target) do |file|
        next if ! File.exist? file
        next if File.directory? file
        if self.class.determine_rule @remove_missing_rules, file
          FileUtils.rm file unless files_to_keep.include? file
        end
      end

      delete_empty_directories(target)
    end

    def delete_empty_directories directory
      Dir.entries(directory).delete_if {|x| x =~ /^\.+$/ }.each do |dir|
        dir = File.join(directory, dir)
        next unless File.directory?(dir)
        delete_empty_directories dir unless dir == directory
        FileUtils.rm_r dir if Dir.entries(dir).delete_if { |x| x=~ /^\.+$/ }.empty?
      end
    end

    private
    
    def determine_path audiofile_or_path, primary, target, encoding
      file = audiofile_or_path.kind_of?(AudioFile) ? audiofile_or_path.path : audiofile_or_path

      path = self.class.determine_rule @path_rules, audiofile_or_path
      if path == :original
        relative = Pathname.new(file).relative_path_from(Pathname.new(primary))
        path = File.expand_path(File.join(target, relative))
        path = path.chomp(File.extname path)
      else
        # Not done yet: 
        artist = artist
        album = album
        track = track
        title = title
        path = ERB.new(File.join(@target, path)).result(binding)
      end
      
      ext = if [:reencode, :copy].include?(encoding[0])
              File.extname file
            else
              encoding[0]
            end
      ext = '.' + ext if ext[0..0] != '.' 

      return path + ext
    end

    def separate_input arg, default_input, default_output='', &block
      if arg.kind_of? Hash 
        raise "Hash must have one key-value pair." unless arg.size == 1
        input = arg.keys.first
        output = arg.values.first
      else
        if block 
          input = !arg.nil? ? arg : default_input
          output = default_output
        else
          input = default_input
          output = !arg.nil? ? arg : default_output
        end
      end
      input = Array(input) unless input.kind_of? Array 
      return input, output
    end

    public

    def encode arg=[], &block
      input, output = separate_input arg, [:audio], [], &block
      output = Array(output) unless output.kind_of? Array 

      if (output & [:lossless, :lossy, :everything, :nonaudio, :audio]) != []
        raise "Target specifier symbols are not valid for output." 
      end
      raise "No output format specified." if !block && output.empty?

      unless block 
        sym = []; int = []; str = []; other = 0
        output.each do |x| 
          if x.kind_of? Symbol
            sym << x
          elsif x.kind_of? Numeric
            int << x
          elsif x.kind_of? String
            str << x
            else
            other += 1
          end
        end
      end

      if [:everything, :nonaudio] & input != []
        unless ([:copy, :skip] & output != []) || block
          raise "only valid targets for :everything and :nonaudio are :copy and :skip" 
        end
        raise "Bitrate not allowed with :everything and :nonaudio." if int.size > 0
      end

      unless block || 
        (sym.size == 1 && int.empty? && str.empty? && other == 0) || 
        (str.size + int.size >= 1 && str.size < 2 && int.size < 2 && other == 0 && sym.empty?)
        raise "Output format incorrectly specified."
      end
      
      output = if ! sym.empty? 
                 [sym[0]]
               else
                 int.empty? ? [str[0]] : [str[0], int[0]]
               end

      input = InputRules.new(input, &block)
      @encode_rules.delete_if { |x| x[0] == input }
      @encode_rules << [input, output]
    end

    def skip arg=[]
      encode(arg=>:skip)
    end

    def copy arg=[]
      encode(arg=>:copy)
    end

    def path arg=[], &block
      # TODO: implement configurable paths
      input, output = separate_input arg, [:audio], '', &block
      raise "not implemented yet" unless output==:original
      raise "No output path specified." if !block && output == ''
      raise "Output path incorrectly specified." unless block || output == :original || output.kind_of?(String)
      if [:everything, :nonaudio] & input != []
        raise unless (output == :original) || block
      end

      input = InputRules.new(input, &block)
      @path_rules.delete_if { |x| x[0] == input }
      @path_rules << [input, output]
    end

    def options arg=[], &block
      input, output = separate_input arg, [:audio], '', &block
      raise "Output path incorrectly specified." unless block || output.kind_of?(String)
      raise if [:everything, :nonaudio] & input != []

      input = InputRules.new(input, &block)
      @option_rules.delete_if { |x| x[0] == input }
      @option_rules << [input, output]
    end

    def effect_options arg=[], &block
      input, output = separate_input arg, [:audio], '', &block
      raise "Effect incorrectly specified." unless block || output.kind_of?(String)
      raise if [:everything, :nonaudio] & input != []

      input = InputRules.new(input, &block)
      @effect_option_rules.delete_if { |x| x[0] == input }
      @effect_option_rules << [input, output]
    end

    def clobber arg=[], &block
      input, output = separate_input arg, [:everything], true, &block
      raise "Effect incorrectly specified." unless block ||
        [String, NilClass, TrueClass, FalseClass].include?(output.class) || output == :rename

      input = InputRules.new(input, &block)
      @clobber_rules.delete_if { |x| x[0] == input }
      @clobber_rules << [input, output]
    end

    def remove_missing arg=[], &block
      input, output = separate_input arg, [:everything], true, &block
      raise "Effect incorrectly specified." unless block ||
        [NilClass, TrueClass, FalseClass].include?(output.class)

      input = InputRules.new(input, &block)
      @remove_missing_rules.delete_if { |x| x[0] == input }
      @remove_missing_rules << [input, output]
    end

  end

  def self.generate *args, &block
    g = Generator.new(&block)
    g.generate(*args)
  end

end

# tp = ThreadPool.new(2)

# int_level = 0
# trap("INT") do 
#   if int_level == 0 
#     int_level += 1
#     puts "Will stop after current processes are finished; press CTRL-C again to stop immediately."
#     tp.stop 
#     abort
#   else
#     tp.kill
#   end
# end

# tp.join
