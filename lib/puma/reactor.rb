require 'puma/util'
require 'puma/minissl'

module Puma
  class Reactor
    DefaultSleepFor = 5

    def initialize(server, app_pool)
      @server = server
      @events = server.events
      @app_pool = app_pool

      @mutex = Mutex.new
      @ready, @trigger = Puma::Util.pipe
      @input = []
      @sleep_for = DefaultSleepFor
      @timeouts = []

      @sockets = [@ready]
      @t = TimeTracker.new :idle
      @t.start
    end

    private

    def run_internal
      sockets = @sockets

      while true
        @t.to :run_internal
        begin
          ready = @t.into(:select) { IO.select sockets, nil, nil, @sleep_for }
        rescue IOError => e
          if sockets.any? { |socket| socket.closed? }
            STDERR.puts "Error in select: #{e.message} (#{e.class})"
            STDERR.puts e.backtrace
            sockets = sockets.reject { |socket| socket.closed? }
            retry
          else
            raise
          end
        end

        if ready and reads = ready[0]
          reads.each do |c|
            if c == @ready
              @t.into(:pipe_command) do
              @mutex.synchronize do
                case @ready.read(1)
                when "*"
                  sockets += @input
                  @input.clear
                when "c"
                  sockets.delete_if do |s|
                    if s == @ready
                      false
                    else
                      s.close
                      true
                    end
                  end
                when "!"
                  return
                end
              end
	      end
            else
              # We have to be sure to remove it from the timeout
              # list or we'll accidentally close the socket when
              # it's in use!
              if c.timeout_at
		@t.into(:timeout_delete) do
                @mutex.synchronize do
                  @timeouts.delete c
                end
		end
              end

	      @t.to :client_io
              begin
                if c.into(:try_to_finish) { c.try_to_finish }
                  @t.into(:client_to_pool) do
                  @app_pool << c
                  sockets.delete c
		  end
                end

              # SSL handshake failure
              rescue MiniSSL::SSLError => e
                ssl_socket = c.io
                addr = ssl_socket.peeraddr.last
                cert = ssl_socket.peercert

		c.to :sslerror
                c.close
                sockets.delete c

                @events.ssl_error @server, addr, cert, e

              # The client doesn't know HTTP well
              rescue HttpParserError => e
                c.to :parser_error
                c.write_400
                c.close

                sockets.delete c

                @events.parse_error @server, c.env, e
              rescue StandardError => e
                c.to :standard_error
                c.write_500
                c.close

                sockets.delete c
              end
            end
          end
        end

	@t.to :timeout_management
        unless @timeouts.empty?
          @mutex.synchronize do
            @t.into(:timeout_discard) do
            now = Time.now

            while @timeouts.first.timeout_at < now
              c = @timeouts.shift
	      c.to :timeouted
              c.write_408 if c.in_data_phase
              c.close
              sockets.delete c

              break if @timeouts.empty?
            end
	    end

	    @t.into(:calculate_sleep) { calculate_sleep }
          end
        end
      end
    end

    public

    def run
      run_internal
    ensure
      @trigger.close
      @ready.close
      @t.stop
    end

    def run_in_thread
      @thread = Thread.new do
        begin
          run_internal
        rescue StandardError => e
          @t.to :standard_error
          STDERR.puts "Error in reactor loop escaped: #{e.message} (#{e.class})"
          STDERR.puts e.backtrace
          retry
        ensure
          @t.to :closing
          @trigger.close
          @ready.close
	  @t.stop
        end
      end
    end

    def calculate_sleep
      if @timeouts.empty?
        @sleep_for = DefaultSleepFor
      else
        diff = @timeouts.first.timeout_at.to_f - Time.now.to_f

        if diff < 0.0
          @sleep_for = 0
        else
          @sleep_for = diff
        end
      end
    end

    def add(c)
      @t.into(:client_add) do
      @mutex.synchronize do
        c.to :reactor
        @input << c
        @trigger << "*"

        if c.timeout_at
          c.into(:reactor_sort) do
            @timeouts << c
            @timeouts.sort! { |a,b| a.timeout_at <=> b.timeout_at }

            calculate_sleep
          end
        end
      end
      end
    end

    # Close all watched sockets and clear them from being watched
    def clear!
      begin
        @trigger << "c"
      rescue IOError
      end
    end

    def shutdown
      begin
        @trigger << "!"
      rescue IOError
      end

      @thread.join
    end
  end
end
