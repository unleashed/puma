module Puma
  class TimeTracker
    attr_reader :seqs

    def initialize(initial_state)
      @initial_state = initial_state
      @seqs = []
      @stop_blk = block_given? ? Proc.new : lambda { |tt| tt.log(STDERR) if tt.all_time > 0.1 }
    end

    def start(state: nil, now: Time.now)
      @seqs << TimeSequence.new(state || @initial_state, now)
    end

    def stop(now = Time.now)
      @seqs.last.close now
      @stop_blk.call self
    end

    def reset(state: nil, now: Time.now)
      stop now if @seqs.any?
      start(state: state, now: now)
    end

    def totals(now = Time.now)
      @seqs.map { |s| s.totals(now) }
    end

    def all_totals(now = Time.now)
      totals.inject(Hash.new { |h, k| h[k] = 0.0 }) do |acc, h|
        h.each do |k, v|
          acc[k] += v
        end
        acc
      end
    end

    def log(out=STDOUT)
      out.puts("*** SLOW ***\n\n#{all_totals.inspect}\n!!!!!!")
    end

    def all_time
      all_totals.inject(0.0) do |acc, (h, k)|
        acc += k
      end
    end

    def to(q, now = Time.now)
      @seqs.last.to q, now
    end

    def into(q, **opts, &blk)
      @seqs.last.into q, **opts, &blk
    end
  end
end
