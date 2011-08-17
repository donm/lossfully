module Lossfully
  LOSSLESS_TYPES = %w(wav flac wv sox).map(&:to_sym)

  class InputRules
    include Comparable

    def initialize array=[], &block
      raise unless array.kind_of? Array
      
      @block = block 

      array.each do |x|
        @type = x if x.kind_of? Symbol
        @max_bitrate = x if x.kind_of? Numeric
        if x.kind_of? String 
          @extension = (x[0..0] == '.') || x== '' ? x : '.' + x
        end
        @regexp = x if x.kind_of? Regexp
      end
      @type ||= :everything
      @max_bitrate ||= 0
      @extension ||= ''
      @regexp ||= //
    end

    attr_reader :block, :extension, :regexp, :type, :max_bitrate

    def test file_or_path
      if file_or_path.kind_of? AudioFile
        file = file_or_path
      else
        path = file_or_path
        if AudioFile.is_audio? path
          file = AudioFile.new path
        else
          return false unless [:everything, :nonaudio].include?(@type)
          return false unless path =~ @regexp
          (return block.call(path)) if @block
          return true
        end
      end
      
      if @type != :everything
        if @type == :lossy 
          return false if LOSSLESS_TYPES.include? file.type
        elsif @type == :lossless
          return false unless LOSSLESS_TYPES.include? file.type
        elsif @type == :audio
          return false unless file.is_audio?
        elsif @type == :nonaudio
          return false if file.is_audio?
        else
          v = [:vorbis, :ogg]
          return false unless (file.type == @type) || 
            (v.include?(file.type) && v.include?(@type))
        end
      end
      
      if @max_bitrate > 0 
        return false unless file.bitrate_kbps > @max_bitrate
      end

      if @extension != ''
        return false unless File.extname(file.path) == @extension
      end

      if @regexp != // 
        return false unless file.path =~ @regexp
      end

      if @block
        return block.call(file.path)
      end

      return true
    end

    # Order by strictness, which is the proper order to test things in
    def <=> x
      -1 * compare_strictness(x)
    end

    # return -1 if self is less strict, 1 if x is more strict
    def compare_strictness x
      return nil unless x.class == self.class

      if @type != x.type
        return -1 if @type == :everything
        return 1 if x.type == :everything
        return -1 if @type == :audio
        return 1 if x.type == :audio
        # these don't have to be comparable since they're mutual exclusive
        return -1 if @type == :nonaudio
        return 1 if x.type == :nonaudio
        return -1 if @type == :lossless
        return 1 if x.type == :lossless
        return -1 if @type == :lossy
        return 1 if x.type == :lossy
        return -1 * (@type.to_s <=> x.type.to_s)
      end

      if @extension != x.extension
        return -1 if @extension == '' 
        return 1 if x.extension == '' 
        return -1 * (@extension <=> x.extension)
      end

      b = @max_bitrate <=> x.max_bitrate
      return b unless b == 0
      
      if @regexp != x.regexp
        return -1 if @regexp == //
        return 1 if x.regexp == //
        return nil
      end

      if @block || x.block
        return nil if @block && x.block
        return -1 if ! @block
        return 1 if ! x.block
      end

      return 0
    end
  end

end

