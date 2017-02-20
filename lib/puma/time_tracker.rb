module Puma
  class TimeTracker
    attr_reader :seqs

    def initialize(initial_state)
      @initial_state = initial_state
      @seqs = []
    end

    def start(state: nil, now: Time.now)
      @seqs << TimeSequence.new(state || @initial_state, now)
    end

    def stop(now = Time.now)
      @seqs.last.close now
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

    def to(q, now = Time.now)
      @seqs.last.to q, now
    end

    def into(q, **opts, &blk)
      @seqs.last.into q, **opts, &blk
    end
  end
end
