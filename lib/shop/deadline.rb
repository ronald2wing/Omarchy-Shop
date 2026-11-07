# Shop::Deadline: a time budget on the monotonic clock, shared by every step of one operation.

module Shop
  class Deadline
    # The least a capped step gets: a nearly spent budget still yields a
    # well-formed child deadline, which times out at once.
    MIN_SECONDS = 0.05

    def initialize(seconds)
      @expires_at = Deadline.now + seconds
    end

    def self.now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    # Seconds left; zero or negative once expired.
    def remaining
      @expires_at - Deadline.now
    end

    def expired?
      remaining <= 0
    end

    # The smaller of `seconds` and what is left, never below MIN_SECONDS.
    def cap(seconds)
      [[seconds, remaining].min, MIN_SECONDS].max
    end
  end
end
