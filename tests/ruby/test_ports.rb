# Shop::Ports: free loopback port and the /proc group-ownership proof.

require_relative 'support'
require 'socket'

port = Shop::Ports.free_loopback_port
assert(Shop::Ports::USABLE.cover?(port), 'a free unprivileged port')
assert(!Shop::Ports.connectable?(port), 'nothing listens there yet')

# A listener in another process group: connectable but not ours.
rd, wr = IO.pipe
pid = Process.spawn(RUBY, '--disable-gems', '-rsocket', '-e',
                    "s = TCPServer.new('127.0.0.1', #{port}); $stdout.puts 'up'; $stdout.flush; loop { (s.accept.close rescue nil) }",
                    pgroup: true, out: wr)
wr.close
begin
  assert_eq(rd.gets&.strip, 'up', 'listener started')
  assert(Shop::Ports.connectable?(port), 'connectable')
  assert(Shop::Ports.listen_inodes(port).size == 1, 'one LISTEN inode on 127.0.0.1:port')
  assert(Shop::Ports.listening_in_group?(port, pid), 'the socket belongs to the listener group')
  assert(!Shop::Ports.listening_in_group?(port, Process.getpgrp), 'not to ours (foreign listener)')
  assert(!Shop::Ports.ready?(port, Process.getpgrp), 'so never ready for us')
ensure
  Process.kill(:KILL, -pid)
  Process.wait(pid)
end
assert(!Shop::Ports.listening_in_group?(port, pid), 'gone after the listener exits')

# A listener that is a non-leader member of the group (the CLI's node child
# under the supervised leader) counts: membership is ProcessGroup.members,
# the supervisor's own definition, not pid == pgid.
port2 = Shop::Ports.free_loopback_port
rd, wr = IO.pipe
child = "s = TCPServer.new('127.0.0.1', #{port2}); $stdout.puts Process.pid; $stdout.flush; loop { (s.accept.close rescue nil) }"
leader = Process.spawn(RUBY, '--disable-gems', '-e',
                       "Process.wait(Process.spawn(#{RUBY.inspect}, '--disable-gems', '-rsocket', '-e', #{child.inspect}))",
                       pgroup: true, out: wr)
wr.close
begin
  member = rd.gets.to_i
  assert(member.positive? && member != leader, 'the listener is a separate member of the group')
  assert(Shop::ProcessGroup.members(leader).include?(member), 'ProcessGroup.members sees the member')
  assert(Shop::Ports.listening_in_group?(port2, leader), "a member's socket belongs to the group")
  assert(!Shop::Ports.listening_in_group?(port2, Process.getpgrp), 'and not to ours')
ensure
  Process.kill(:KILL, -leader)
  Process.wait(leader)
end
