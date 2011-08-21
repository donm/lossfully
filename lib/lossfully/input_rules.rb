#--
# Copyright (C) 2011 Don March
#
# This file is part of Lossfully.
#
# Lossfully is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#  
# Lossfully is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see
# <http://www.gnu.org/licenses/>.
#++

module Lossfully
  LOSSLESS_TYPES = %w(wav flac wv sox).map(&:to_sym)

  # The InputRules class wraps up conditions and provides a way to
  # test if a file meets those conditions.  It also allows the
  # conditions to be sorted so that more restrictive conditions are
  # tried before less restrictive.  The sorting hopefully does what
  # seems natural; it looks at first at the regexp, then the file type
  # (as returned by soxi -t), the file extension, the bitrate
  # threshold, and finally if a block is given.  For example, the
  # following encode rules are shown in the order that they would be
  # tested against every file (even though the rules would be checked
  # in this order even if the below encode statements were in a
  # different order):
  #
  #   encode [:mp3, 128, /bach/] do 
  #     ... 
  #   end
  #   encode [:mp3, 128, /bach/] => ...
  #   encode [:mp3, /bach/] => ...
  #   encode [:mp3, 128] => ...
  #   encode :mp3 => ...
  #   encode :lossy => ...
  #   encode :audio => ...
  #   encode :everything => ...
  #
  # It's obviously only a partial order; see the code for
  # compare_strictness if you need to know exactly what it's doing.
  #
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
      file = if file_or_path.kind_of? AudioFile
               file_or_path
             else
               AudioFile.new(file_or_path)
             end
#      unless file.is_audio?
#        return false unless [:everything, :nonaudio].include?(@type)
#        return false unless file.path =~ @regexp
#        (return block.call(file.path)) if @block
#        return true
#      end

      if @type != :everything
        if [:audio, :lossy, :lossless].include? @type
          return false unless file.is_audio?
        end

        if @type == :lossy 
          return false if LOSSLESS_TYPES.include? file.type
        elsif @type == :lossless
          return false unless LOSSLESS_TYPES.include? file.type
        elsif @type == :nonaudio
          return false if file.is_audio?
        elsif @type != :audio
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
        # return block.call(file.path)
        # TODO: decide if this should be file or file.path
        return block.call(file)
      end

      return true
    end

    # Order by strictness, which is the proper order to test things in
    def <=> x
      -1 * compare_strictness(x)
    end

    # return -1 if self is less strict, 1 if self is more strict
    def compare_strictness x
      return nil unless x.class == self.class

      if @regexp != x.regexp
        return -1 if @regexp == //
        return 1 if x.regexp == //
        return nil
      end

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
      
      if @block || x.block
        return nil if @block && x.block
        return -1 if ! @block
        return 1 if ! x.block
      end

      return 0
    end
  end

end

