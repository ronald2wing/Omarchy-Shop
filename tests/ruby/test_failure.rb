# Shop::Failure: its exit status, the error object (cleaned message, extra fields) and its details.

require_relative 'support'

F = Shop::Failure

assert_eq(%w[timeout terminated store_busy].map { |c| F.new(c, 'x').exit_code }, [124, 143, 1], 'timeout exits 124, terminated 143, any other code 1')

e = F.new('unsafe_folder', "bad\e[31m \u0007folder", reason: 'symlink')
assert_eq(e.to_error, { 'code' => 'unsafe_folder', 'message' => 'bad folder', 'reason' => 'symlink' }, 'to_error: cleaned message, extra fields inside')
assert_eq(F.new('cli_failed', 'x' * 300).to_error['message'].length, 200, 'the message is capped at 200 characters')

assert_eq(F.new('cli_failed', 'x', details: ['line']).details, ['line'], 'details ride along, outside the error object')

assert(Shop::Failure.new('cli_failed', 'x', details: []).details.nil?, 'empty details are no details')
assert_eq(Shop::Failure.new('cli_failed', 'x', details: ['a']).details, ['a'], 'details are kept')
