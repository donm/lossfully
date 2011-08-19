require 'test/unit'

$:.unshift File.dirname(__FILE__) + '/../lib'
require 'lossfully'

module TestLossfully
  class TestInputRules < Test::Unit::TestCase
  
    def test_test
      r1 = Lossfully::InputRules.new [:flac]
      r2 = Lossfully::InputRules.new [:everything]
      r2 = Lossfully::InputRules.new [:nonaudio]
      f1 = 'test/data/text.txt'
      assert !(r1.test f1)
      assert r2.test f1

      r1 = Lossfully::InputRules.new [:flac]
      r2 = Lossfully::InputRules.new [:ogg]
      r3 = Lossfully::InputRules.new [:everything]
      r4 = Lossfully::InputRules.new [:lossy]
      r5 = Lossfully::InputRules.new [:lossless]
      r6 = Lossfully::InputRules.new [:audio]
      r7 = Lossfully::InputRules.new [:nonaudio]
      f1 = 'test/data/so_sad.flac'
      f2 = 'test/data/so_sad.ogg'
      assert r1.test f1
      assert r2.test f2
      assert r3.test f1
      assert r3.test f2
      assert r4.test f2
      assert r5.test f1
      assert r6.test f1
      assert r6.test f2
      assert ! (r4.test f1)
      assert ! (r5.test f2)

      r1 = Lossfully::InputRules.new [100]
      r2 = Lossfully::InputRules.new [128]
      f1 = 'test/data/so_sad.ogg'
      assert r1.test f1
      assert !(r2.test f1)      

      r1 = Lossfully::InputRules.new ['.ogg']
      r2 = Lossfully::InputRules.new ['.flac']
      f1 = 'test/data/so_sad.ogg'
      f2 = 'test/data/so_sad.flac'
      assert r1.test f1
      assert r2.test f2
      assert !(r1.test f2)
      assert !(r2.test f1)

      r1 = Lossfully::InputRules.new [/sad/]
      r2 = Lossfully::InputRules.new [/happy/]
      f1 = Lossfully::AudioFile.new 'test/data/so_sad.ogg'
      assert r1.test f1
      assert !(r2.test f1)

      r1 = Lossfully::InputRules.new do |f|
        [:mp3] if File.dirname(f.path) == 'test/data' 
      end
      f1 = Lossfully::AudioFile.new 'test/data/so_sad.ogg'
      assert r1.test f1
      
      r1 = Lossfully::InputRules.new [:ogg, 100] do |f|
        [:mp3] if File.dirname(f.path) == 'test/data' 
      end
      assert r1.test f1

      r1 = Lossfully::InputRules.new [:ogg, 128] do |f|
        [:mp3] if File.dirname(f.path) == 'test/data' 
      end
      assert !(r1.test f1)
    end

    def test_comparison
      r1 = Lossfully::InputRules.new [:mp3, /mp3/]
      r2 = Lossfully::InputRules.new [:mp3, /mp3/]
      r3 = Lossfully::InputRules.new [:mp3]
      r4 = Lossfully::InputRules.new { false }
      a = [r1]
      assert a.include? r2
      assert !(a.include? r3)
      assert !(a.include? r4)

      r1 = Lossfully::InputRules.new { false }
      r2 = Lossfully::InputRules.new 
      r3 = Lossfully::InputRules.new [:mp3, /regexp/, 192]
      r4 = Lossfully::InputRules.new [:mp3, /regexp/, 192] do false end
      assert r1 < r2
      assert r3 < r1
      assert r4 < r3

      r1 = Lossfully::InputRules.new [:everything]
      r2 = Lossfully::InputRules.new [:lossy]
      r3 = Lossfully::InputRules.new [:lossless]
      r4 = Lossfully::InputRules.new [:audio]
      r5 = Lossfully::InputRules.new [:nonaudio]
      assert r2 < r1
      assert r3 < r1
      assert r4 < r1
      assert r5 < r1
      assert r2 < r4
      assert r3 < r4

      r1 = Lossfully::InputRules.new ['']
      r2 = Lossfully::InputRules.new ['ogg']
      assert r2 < r1

      r1 = Lossfully::InputRules.new [192]
      r2 = Lossfully::InputRules.new [128]
      assert r1 < r2

      r1 = Lossfully::InputRules.new [//]
      r2 = Lossfully::InputRules.new [/a/]
      r3 = Lossfully::InputRules.new [/b/]
      assert r2 < r1
      assert_not_equal r2, r3

      r1 = Lossfully::InputRules.new [:ogg, 192]
      r2 = Lossfully::InputRules.new [:ogg, /a/]
      assert r2 < r1
    end

  end
end
