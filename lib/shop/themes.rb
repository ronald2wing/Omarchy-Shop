# Shop::Themes: the CLI's theme data: `theme list` and resolving a target (live or id) to a theme, push and pull argv, and their results and per-file issues.

module Shop
  module Themes
    MAX_THEMES = 200
    MAX_ISSUES = 20

    module_function

    # The one theme shape Shop emits ({id, name, role}: theme lists, push
    # and pull results, backup rows): the id as a string, the remote name
    # cleaned ("Theme <id>" when empty), the role as the CLI reports it or
    # "unknown".
    def theme_hash(id, name, role)
      { 'id' => id.to_s, 'name' => Validate.label(name.to_s) || "Theme #{id}", 'role' => Validate.role(role) }
    end

    # [{id, name, role}] from {"themes":[{"id","name","role"}]}.
    def parse_list(body)
      themes = body['themes']
      raise Failure.new('bad_response', 'theme list: no themes array') unless themes.is_a?(Array)

      themes.first(MAX_THEMES).filter_map do |t|
        next unless t.is_a?(Hash) && Validate.theme_id?(t['id'].to_s)

        theme_hash(t['id'], t['name'], t['role'])
      end
    end

    # The theme for target "live" (the role) or an id; theme_not_found otherwise.
    def resolve(themes, target)
      theme = target == 'live' ? themes.find { |t| live?(t) } : themes.find { |t| t['id'] == target.to_s }
      return theme if theme

      raise Failure.new('theme_not_found', target == 'live' ? 'the store has no live theme' : "the store has no theme #{target}")
    end

    def live?(theme) = theme['role'] == 'live'

    # `theme list` for `domain` (CI, private cwd).
    def list(located, domain, deadline:)
      parse_list(Shopify.call(located, ['theme', 'list', "--store=#{domain}", '--json', '--no-input'], deadline: deadline))
    end

    # Always --nodelete; --allow-live only when the resolved target is live.
    def push_args(domain, theme, folder)
      args = ['theme', 'push', "--store=#{domain}", "--theme=#{theme['id']}", "--path=#{folder}", '--nodelete', '--json', '--no-input']
      args << '--allow-live' if live?(theme)
      args
    end

    # Always --nodelete and --force. The pinned CLI's pull refuses, under
    # --no-input, any target folder that is not theme-shaped or that is a git
    # working tree with uncommitted or untracked changes (the normal state of
    # a theme developer's checkout); --force skips that prompt. Shop's own
    # gate is stronger and runs first: ThemeFolder.check!(mode: :pull) and
    # the folder copy before the pull.
    def pull_args(domain, theme, folder)
      ['theme', 'pull', "--store=#{domain}", "--theme=#{theme['id']}", "--path=#{folder}", '--nodelete', '--force', '--json', '--no-input']
    end

    # The push/pull JSON result of the pinned CLI. Push: {"status":
    # "success"|"partial","changed","theme":{...},"issues":[{filePath,
    # message}]} ('partial' exits 1; nothing uploaded is "success" with
    # changed: false) or {"status":"skipped","reason":"unsafe-directory"}.
    # Pull: {"status":"success","changed","directory","theme"} or skipped,
    # never 'partial' and never issues (a failed download is an error JSON,
    # exit 1), so with pull: true any status but 'success' fails (an
    # incomplete backup pull is no backup). Returns {partial:, issues:
    # [issue rows]}; a skipped run fails.
    def sync_result(body, pull: false)
      status = body['status']
      case status
      when 'success', *('partial' unless pull)
        { partial: status == 'partial', issues: issues(body['issues']) }
      when 'skipped'
        raise Failure.new('cli_failed', "folder skipped: #{Text.quote(body['reason'])}")
      else
        raise Failure.new('bad_response', 'theme push/pull: unexpected status')
      end
    end

    # The files the CLI rejected, from its `issues` list ({filePath,
    # message} objects: a partial push's result, a failed push's
    # error.details): the first MAX_ISSUES as warning rows; anything that is
    # not such an object is skipped.
    def issues(list)
      return [] unless list.is_a?(Array)

      list.select { |raw| raw.is_a?(Hash) }.first(MAX_ISSUES).map { |raw| issue(raw) }
    end

    # How many rejected files the list names (issues keeps MAX_ISSUES).
    def issue_count(list)
      list.is_a?(Array) ? list.count { |raw| raw.is_a?(Hash) } : 0
    end

    # One file the CLI rejected ({filePath, message}) as the warning row
    # {kind: 'issue', path, message}: the path relative to the theme
    # (ThemeFolder.theme_relative, the one rule for the CLI's filePath),
    # both cleaned.
    def issue(raw)
      { 'kind' => 'issue', 'path' => Text.clean(ThemeFolder.theme_relative(raw['filePath'].to_s), 120),
        'message' => Text.clean(raw['message'].to_s, 160) }
    end

    # "path: message" for one issue row.
    def issue_line(row)
      "#{row['path']}: #{row['message']}"
    end
  end
end
