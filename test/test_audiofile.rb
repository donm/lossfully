require 'test/unit'

$:.unshift File.dirname(__FILE__) + '/../lib'
require 'lossfully'

module TestLossfully
  class TestAudioFile < Test::Unit::TestCase
  
    def test_encoding
      assert_raise RuntimeError do Lossfully::AudioFile.encoding('test/data/this_file_does_not_exist') end
      assert ! Lossfully::AudioFile.is_audio?('test/data/text.txt')
      assert Lossfully::AudioFile.encoding('test/data/so_sad.ogg')
    end
    
    def test_bitrate
      assert_equal '114k', Lossfully::AudioFile.bitrate('test/data/so_sad.ogg')      
    end

    def test_bitrate_kbps
      assert_equal 114, Lossfully::AudioFile.bitrate_kbps('test/data/so_sad.ogg')
      assert_equal 2820, Lossfully::AudioFile.bitrate_kbps('test/data/so_sad.sox')
    end

    def test_duration
      f = Lossfully::AudioFile.new('test/data/so_sad.ogg')      
      assert_equal 6.047959, f.duration
    end

    def test_class_encode
      input  = 'test/data/so_sad.flac'
      output = 'test/data/so_sad.wav'
      FileUtils.rm output if File.exist? output
      Lossfully::AudioFile.encode input, output
      assert_equal :wav, Lossfully::AudioFile.type(output)
    end

    def test_encode
      input = 'test/data/so_sad.flac'
      f = Lossfully::AudioFile.new input
      output = 'test/data/so_sad.wav'
      FileUtils.rm output if File.exist? output
      f.encode output
      assert_equal :wav, Lossfully::AudioFile.type(output)
    end

  end
end
