require 'find'
require 'pathname'
require 'erb'
require 'fileutils'

# TODO: test if necessary binaries are installed
# TODO: test if soxi compiled with LAME

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
      
      encode :copy
      path :everything => :original
      clobber true
      remove_missing true
      options ''
      effect_options ''

      if block_given?
        if block.arity == 1
          yield self
        else
          instance_eval(&block)
        end
      end 
    end
    
    def generate hash
      raise "Requires a Hash." unless hash.kind_of? Hash
      raise "Requires a Hash with one key-value pair." unless hash.size == 1
      
      primary = hash.keys.first
      target  = hash.values.first

      raise "Converting from multiple directories is not supported" if primary.kind_of? Array
      raise "Writing to multiple directories is not supported" if target.kind_of? Array
      primary = File.expand_path primary, File.dirname($0)
      target = File.expand_path target, File.dirname($0)

      raise "Overwriting original library not supported." if primary == target

      [@encode_rules,
       @path_rules,
       @option_rules,
       @effect_option_rules,
       @clobber_rules,
       @remove_missing_rules].each do |a|
        self.class.sort_by_rules! a
      end

      actions = []
      files_to_keep = []

      Find.find(primary) do |file|
        next if File.directory? file
        
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
        
        if encoding[0] == :copy
          actions << lambda do
            puts path
            FileUtils.mkdir_p File.dirname(path)
            FileUtils.cp(file, path) 
          end
        else
          options = self.class.determine_rule @option_rules, file
          effect_options = self.class.determine_rule @effect_option_rules, file
          actions << lambda do
            puts path
            FileUtils.mkdir_p File.dirname(path)
            options = "-C #{encoding[1]} " + options if encoding[1].kind_of? Numeric
            AudioFile.encode file, path, options, effect_options 
          end
        end
      end

      files_to_keep.uniq!

      Find.find(target) do |file|
        next if ! File.exist? file
        next if File.directory? file
        if self.class.determine_rule @remove_missing_rules, file
          FileUtils.rm file unless files_to_keep.include? file
        end
      end

      tp = ThreadPool.new(2) 
      actions.each { |a| tp << a }
      tp.join

      Find.find(target) do |file|
        next unless File.directory? file
        FileUtils.rm_r file if Dir.entries(file).delete_if { |x| x=~ /^\.+$/ }.empty?
      end
    end

    private
    
    def determine_path file, primary, target, encoding
      path = self.class.determine_rule @path_rules, file
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
      input, output = separate_input arg, [:everything], [], &block
      output = Array(output) unless output.kind_of? Array 

      if (output & [:lossless, :lossy, :everything, :nonaudio, :audio]) != []
        raise "Target specifier symbols are not valid for output." 
      end
      raise "No output format specified." if !block && output.empty?
      if [:everything, :nonaudio] & input != []
        unless ([:copy, :skip] & output != []) || block
          raise "only valid targets for :everything and :nonaudio are :copy and :skip" 
        end
      end

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

      unless block || 
        (sym.size == 1 && int.empty? && str.empty? && other == 0) || 
        (str.size + int.size >= 1 && str.size < 2 && int.size < 2 && other == 0 && sym.empty?)
        raise "Output format incorrectly specified."
        if ! sym.empty? 
          output = [sym[0]]
        else
          output = int.empty? ? [str[0]] : [str[0], int[0]]
        end
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
