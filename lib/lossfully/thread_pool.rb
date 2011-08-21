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

require 'thread'
require 'timeout'

module Lossfully

# There's (at least) two ways to do this: 1) the Ruby Recipes way,
# which is to make a thread for every incoming task, but put it to
# sleep until there's room in the pool for another task, or 2) have a
# pool of threads that eat tasks from a queue.  This implements (2),
# mainly because it seemed more fun to me.  But also because it
# doesn't require the explicit use of Mutexes at all; it uses them,
# for the sake of sending signals with ConditionVaribles, but if those
# signals aren't received there would be a delay of at most 1 second.
#
# Another useful thing about this implementation is for the case when
# every task you anticipate adding to the ThreadPool of the same
# general form.  Then then ThreadPool can be initialized with a block
# and you can just add objects to the task queue.
#
  class ThreadPool

    DEFAULT_BLOCK = lambda {|block, &blk| block = blk if block_given? ; block.call}

    def initialize(max_size = 1, block=nil, &blk)
      @running = true
      @joining = false
      
      @mutex = Mutex.new
      @cv = ConditionVariable.new
      @max_size = max_size
      block = blk if block_given?
      @block = block.nil? ? DEFAULT_BLOCK : block
      @queue = Queue.new
      @workers = []
      @master = master_thread
      @completed = 0
      @total = 0
    end

    def process (block_or_item=nil, &blk)
      block_or_item = blk if block_given?
      if block_or_item.respond_to?(:call) 
        @queue << block_or_item
      else
        @queue << lambda { @block.call(block_or_item) }
      end
#      @mutex.synchronize { @total +=1 }
      @total += 1
      signal_master
    end

    def current
      @total - @queue.size
    end

    attr_reader :max_size, :mutex, :completed, :total
    alias :enq :process
    alias :dispatch :process
    
    def max_size=(size)
      @max_size = size
      signal_master
    end

    def << block_or_item
      process block_or_item
    end

    def join
      @running = false
      @joining = true
      signal_master
      # A weird bug happens on this next line if you don't test
      # @master.alive?, but only sometimes.  I don't care enough to
      # figure it out right now.
      @master.join if @master.alive?
    end

    def size
      @workers.size
    end

    def queue_size
      @queue.size
    end

    def stop
      @queue.clear
      join
    end

    def kill
      @queue.clear
      @workers.each(&:kill)
      join
    end

    private

    def signal_master
      @mutex.synchronize { @cv.signal }
    end

    def master_thread
      Thread.new do
        while @running || ! @queue.empty?

          @workers ||= []
          @workers.delete_if { |w| ! w.alive? }    

          while @workers.size < @max_size && @queue.size > 0 
            @workers << Thread.new do 
              begin
                if task = @queue.pop(true) rescue nil
                  task.call
                  @mutex.synchronize { @completed +=1 }
                end 
              ensure
                signal_master
              end
            end
          end

          @mutex.synchronize do
            # @cv.wait(@mutex, 1) # can't do this in 1.8.7
            begin
              Timeout::timeout(2) { @cv.wait(@mutex) }
            rescue Timeout::Error
            end
          end
          # This needs to come after the critical section above,
          # otherwise the main thread will have to wait for the timeout
          # before continuing when the ThreadPool is joined.  The rescue
          # below handles exceptions that might have happened in the
          # threads, which will stop the main thread now that they're
          # being joined.
          @workers.each(&:join) if @joining rescue nil
        end
      end
    end
  end
end
