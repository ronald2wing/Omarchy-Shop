# Contract checks over what ships: no agent steering file is tracked, archived or left unignored, and no file cites an internal review or planning id.

require_relative 'support'
require 'find'

Dir.chdir(ROOT) do
  # The agent-file list is .gitignore's "Agent steering files" block, the
  # one parser of it: the header line, then one pattern per line up to the
  # next comment line. A path matches a pattern the way git does: `*` stays
  # within one component, a pattern with an inner slash is anchored at the
  # root, one without matches any component, a trailing `/` a directory.
  agent_patterns = File.read('.gitignore')[/^# Agent steering files[^\n]*\n(.*?)(?=^#|\z)/m, 1].to_s.lines.map(&:strip).reject(&:empty?)
  assert(agent_patterns.include?('AGENTS.md') && agent_patterns.include?('.claude/'),
         ".gitignore's 'Agent steering files' block lists the agent files: #{agent_patterns}")
  agent_file = lambda do |path, dir: false|
    parts = path.split('/')
    agent_patterns.any? do |pat|
      dir_only = pat.end_with?('/')
      pat = pat.chomp('/')
      if pat.include?('/')
        File.fnmatch(pat, path, File::FNM_PATHNAME | File::FNM_DOTMATCH) || path.start_with?("#{pat}/")
      else
        (dir_only && !dir ? parts[0...-1] : parts).any? { |c| File.fnmatch(pat, c, File::FNM_DOTMATCH) }
      end
    end
  end

  tracked = `git ls-files`.lines.map(&:chomp)
  assert(tracked.none? { |f| agent_file.call(f) }, "agent steering files are tracked: #{tracked.select { |f| agent_file.call(f) }}")

  # Whatever exists in the checkout under a pattern is ignored (a negation
  # or a nested .gitignore could un-ignore it), at any depth.
  Find.find('.') do |p|
    path = p.delete_prefix('./')
    next if path == '.'
    Find.prune if path == '.git'
    dir = File.directory?(p) && !File.symlink?(p)
    next unless agent_file.call(path, dir: dir)

    system('git', 'check-ignore', '-q', dir ? "#{path}/" : path) || assert(false, "#{path} is an agent steering file that git does not ignore")
    Find.prune if dir
  end

  # No internal review or planning ids in shipped or test files: a
  # contributor can't look them up. Built from parts so this file doesn't
  # match itself.
  id_re = Regexp.new('\b(?:' + %w[D U R V].map { |c| "#{c}-\\d+" }.join('|') + '|S\d+)\b|' + [0xa7].pack('U') + '|\bplan2?\.md\b|\bWS\d\b')
  repo_files.each do |f|
    next unless File.file?(f)

    text = File.binread(f)
    next if text.include?("\0")

    text.force_encoding(Encoding::UTF_8).scrub.each_line.with_index(1) do |line, n|
      assert(!line.match?(id_re), "#{f}:#{n} cites an internal id: #{line.strip[0, 80]}")
    end
  end

  # The archive of HEAD on a clean tree (the release check); on a dirty
  # tree, the archive of the index as it would be committed.
  clean = `git status --porcelain`.strip.empty?
  tree = clean ? 'HEAD' : `git write-tree 2>/dev/null`.strip
  unless tree.empty?
    listing = `git archive #{tree} | tar -t 2>/dev/null`.lines.map(&:chomp)
    assert(listing.none? { |f| agent_file.call(f) }, "git archive #{clean ? 'HEAD' : 'index'} contains agent files: #{listing.select { |f| agent_file.call(f) }}")
  end
end
