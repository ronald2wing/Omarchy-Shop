# Shop::ProcessGroup: signalling a child's process group and telling from /proc whether anything in it is still alive.

module Shop
  module ProcessGroup
    # How long finish waits for a killed group to be gone, and how often it
    # looks meanwhile.
    GONE_WAIT = 1.0
    GONE_POLL = 0.02

    module_function

    def signal(pgid, sig)
      Process.kill(sig, -pgid)
    rescue Errno::ESRCH, Errno::EPERM
      nil
    end

    # The exit code of a reaped Process::Status: its exit status, or 128 +
    # the signal that killed it; nil when there was nothing to reap.
    def exit_code(status)
      return nil if status.nil?

      status.exitstatus || (128 + status.termsig.to_i)
    end

    # [state, pgrp] of a pid from /proc, or nil.
    def proc_stat(pid)
      raw = File.read("/proc/#{pid}/stat")
      fields = raw[(raw.rindex(')') + 2)..].split
      [fields[0], fields[2].to_i]
    rescue SystemCallError, NoMethodError
      nil
    end

    # True once `pid` has exited (a zombie, or gone).
    def exited?(pid)
      stat = proc_stat(pid)
      stat.nil? || %w[Z X].include?(stat[0])
    end

    # Live (non-zombie) pids in process group `pgid`.
    def members(pgid, except: nil)
      Dir.children('/proc').filter_map do |name|
        next unless name.match?(/\A\d+\z/)

        pid = name.to_i
        next if pid == except

        stat = proc_stat(pid)
        pid if stat && stat[1] == pgid && !%w[Z X].include?(stat[0])
      end
    end

    # True when nothing is left in group `pgid`. kill(0, -pgid) raises ESRCH
    # only when no process, zombie included, is in the group: the common
    # case (a lone leader, already reaped) costs one syscall, and the /proc
    # scan is paid only to tell live members from zombies their new parent
    # has not reaped yet.
    def gone?(pgid)
      Process.kill(0, -pgid)
      members(pgid).empty?
    rescue Errno::ESRCH
      true
    rescue Errno::EPERM
      false
    end

    def wait_gone(pgid)
      until_at = Deadline.now + GONE_WAIT
      loop do
        return true if gone?(pgid)
        return false if Deadline.now >= until_at

        sleep GONE_POLL
      end
    end
  end
end
