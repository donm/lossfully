require 'test/unit'

$:.unshift File.dirname(__FILE__) + '/../lib'
require 'lossfully'

module TestLossfully
  class TestThreadPool < Test::Unit::TestCase

    def test_everything
      a = [] 
      tp = ThreadPool.new(2)
      tp.max_size = 3
      assert_equal 3, tp.max_size
      tp.process { a << 1}
      tp.process { a << 2 }
      tp.process { a << 3 }
      tp.join
      assert a.include? 1
      assert a.include? 2
      assert a.include? 3
    end

    def test_everything_with_auto_blocks
      a = []
      tp = ThreadPool.new(2) do |x|
        a << x
      end
      tp << 1
      tp << 2
      tp << 3
      tp.join
      assert a.include? 1
      assert a.include? 2
      assert a.include? 3
    end

    def test_stop
      tp = ThreadPool.new(2) 
      r1 = false
      r2 = false
      r3 = false

      tp.process { sleep 0.3; r1 = true}
      tp.process { sleep 0.3; r2 = true}
      tp.process { sleep 0.3; r3 = true}
      2.times { Thread.pass } and sleep 0.1
      assert_equal 1, tp.queue_size 
      assert_equal 2, tp.size
      tp.stop
      sleep 0.4

      assert r1, 'first task finished'
      assert r2, 'second task finished'
      assert ! r3, 'third task did not finish'
    end

    def test_kill
      tp = ThreadPool.new(2) 
      r1 = false
      r2 = false
      r3 = false

      tp.process { sleep 0.3; r1 = true}
      tp.process { sleep 0.3; r2 = true}
      tp.process { sleep 0.3; r3 = true}
      2.times { Thread.pass } and sleep 0.1

      tp.kill
      sleep 0.4

      assert ! r1, 'first task did not finished'
      assert ! r2, 'second task did not finished'
      assert ! r3, 'third task did not finish'
    end

  end
end
