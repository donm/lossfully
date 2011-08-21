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

require 'fileutils'

module Lossfully
  class AudioFile

    private
    
    # Raises RuntimeError if +path+ is not a file.
    #
    def self.check_file path
      raise "Does not exist: #{path}" unless File.file? path      
    end

    public

    def self.soxi_command path, options=''
      check_file path

      # system("soxi -V0 #{path}")
      return nil if File.extname(path) == '.m3u'
      p = IO.popen("sox --info -V0 #{options} \"#{path}\"")
      return ((Process.wait2 p.pid)[1] == 0) ? p.gets.chomp : nil
    end

    def self.def_soxi(method, options='')
      class_eval <<-EOM
        def self.#{method} path
          self.soxi_command path, '#{options}'
        end
      EOM
    end

    # Return the encoding of the file ('soxi -e').  If soxi does not
    # recognize the file as audio, return nil.
    # 
    def_soxi :encoding, '-e'

    # Return the file-type as a symbol ('soxi -t').  If soxi does not
    # recognize the file as audio, return nil.
    # 
    def self.type path
      t = soxi_command path, '-t'
      return t ? t.to_sym : nil
    end
    # def_soxi :type, '-t'

    # Return the bitrate of the file as a string ('soxi -B').  If soxi
    # does not recognize the file as audio, return nil.
    #
    def_soxi :bitrate, '-B'

    # Return the bitrate of the file as an integer in kbps ('soxi -B').  If soxi
    # does not recognize the file as audio, return nil.
    #
    def self.bitrate_kbps path
      b = bitrate(path)
      return b.to_f * (b[-1..-1] == 'k' ? 1 : 1000)
    end

    # Return the duration of the file in seconds as a Float 
    # ('soxi -D').  If soxi does not recognize the file as audio, 
    # return nil.
    #
    def self.duration path
      #(soxi_command path, '-D').to_f
      `soxi -V0 -D \"#{path}\"`.chomp.to_f
    end

    class << self 
      alias :is_audio? :type
      alias :length :duration
    end

    def self.encode input_path, output_path, options='', effect_options=''
      FileUtils.mkdir_p(File.dirname(output_path)) unless File.directory? output_path
      system("sox \"#{input_path}\" #{options} \"#{output_path}\" #{effect_options}")
    end

    def initialize path
      @path = path

      # Actually, let's not do this.  This gets checked every time a
      # method is run anyway, so this way we can just use the class as
      # a wrapper around a path string for files that aren't audio.
      #
      # raise "Not recognized as an audio file: #{file}" unless is_audio?
    end

    attr_reader :path

    # This could be done with method_missing.
    def self.delegate_and_memoize(method, class_method=nil)
      class_method ||= method
      class_eval <<-EOM
        def #{method}
          @#{method} ||= self.class.#{class_method}(@path)
        end
      EOM
    end

    def encode output_path, options='', effect_options=''
      self.class.encode @path, output_path, options, effect_options
    end

    delegate_and_memoize :encoding
    delegate_and_memoize :type
    delegate_and_memoize :bitrate
    delegate_and_memoize :bitrate_kbps
    delegate_and_memoize :duration

    alias :length :duration
    alias :is_audio? :type
  end
end
