# Shop::Ports: a free loopback port and the /proc proof that a LISTEN socket belongs to a given process group.

require 'socket'

module Shop
  module Ports
    # The unprivileged ports: a kernel-assigned port outside them is refused.
    USABLE = (1024..65_535)
    # The most open fds a readiness check reads across the group.
    MAX_FDS = 2000
    # How long a readiness probe waits for its loopback connect.
    CONNECT_TIMEOUT = 0.25
    LOOPBACK_V4 = '0100007F'
    LOOPBACK_V6_MAPPED = '0000000000000000FFFF00000100007F'
    LISTEN = '0A'

    module_function

    # Bind 127.0.0.1:0, read the port, close.
    def free_loopback_port
      server = TCPServer.new('127.0.0.1', 0)
      server.addr[1]
    ensure
      server&.close
    end

    # A TCP connect to 127.0.0.1:port succeeds.
    def connectable?(port)
      Socket.tcp('127.0.0.1', port, connect_timeout: CONNECT_TIMEOUT, &:close)
      true
    rescue SystemCallError, IOError, SocketError
      false
    end

    # Inodes of LISTEN sockets on 127.0.0.1:port (v4 and v4-mapped v6).
    def listen_inodes(port)
      hex = format('%04X', port)
      inodes = []
      { '/proc/net/tcp' => LOOPBACK_V4, '/proc/net/tcp6' => LOOPBACK_V6_MAPPED }.each do |file, addr|
        File.foreach(file).drop(1).each do |line|
          f = line.split
          next unless f[1] == "#{addr}:#{hex}" && f[3] == LISTEN

          inodes << f[9]
        end
      rescue SystemCallError
        next
      end
      inodes
    end

    # True when the LISTEN socket on 127.0.0.1:port is an open fd of a
    # process in group `pgid` (ProcessGroup.members, the supervisor's own
    # definition of the group). Bounded to MAX_FDS fds per check; a member
    # that exits between the scan and the fd read is skipped.
    def listening_in_group?(port, pgid)
      wanted = listen_inodes(port).map { |i| "socket:[#{i}]" }
      return false if wanted.empty?

      seen = 0
      ProcessGroup.members(pgid).each do |pid|
        Dir.children("/proc/#{pid}/fd").each do |fd|
          seen += 1
          return false if seen > MAX_FDS

          return true if wanted.include?((File.readlink("/proc/#{pid}/fd/#{fd}") rescue nil))
        end
      rescue SystemCallError
        next
      end
      false
    end

    def ready?(port, pgid)
      connectable?(port) && listening_in_group?(port, pgid)
    end
  end
end
