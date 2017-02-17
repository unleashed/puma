module Puma
  class TimeSequence
    def initialize(initial, now = Time.now)
      @inner = { current: [initial], initial => [[now]] }
      @closed = false
    end

    def current
      @inner[:current].last
    end

    def to(q, now = Time.now)
      current = @inner[:current]
      @inner[current.last].last << now
      @inner[q] ||= []
      @inner[q] << [now]
      current << q
    end

    def close(now = Time.now)
      @closed = true
      @inner[@inner[:current].last].last << now
      @inner.freeze
    end

    def closed?
      @closed
    end

    def inspect
      transitions.map do |t|
        "#{t[:state]}: #{t[:time] || %Q(current since #{t[:start]})}"
      end.join(' -> ')
    end

    def totals(now = Time.now)
      @inner.inject(Hash.new { |h, k| h[k] = 0.0 }) do |acc, (k, v)|
        next acc if k == :current
        acc[k] += v.inject(0.0) { |total, t| total += (t[1] || now) - t[0] }
        acc
      end
    end

    def transitions
      qi = Hash.new { |h, k| h[k] = 0 }
      @inner[:current].inject([]) do |acc, q|
        this_q = @inner[q][qi[q]]
        qi[q] += 1
        finish = this_q[1]
        start = this_q[0]
        acc << { state: q, start: start, finish: finish, time: finish ? finish - start : nil }
      end
    end
  end
end
