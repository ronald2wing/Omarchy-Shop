# Shop::Text: cleaning untrusted text (ANSI, control characters, invalid UTF-8), notification text, CLI diagnostics and natural sort.

module Shop
  module Text
    ANSI_RE = /\e(?:\[[0-?]*[ -\/]*[@-~]|\][^\a\e]*(?:\a|\e\\)|[@-Z\\-_])/
    # Control and format characters (C0, DEL, C1, zero-width and bidi
    # controls) plus the Unicode line and paragraph separators (U+2028,
    # U+2029), which Qt lays out as line breaks even in PlainText. The zero
    # width joiner (U+200D) is kept: it glues emoji sequences in store and
    # product names.
    CONTROL_RE = /[\p{Cc}\p{Cf}\p{Zl}\p{Zp}&&[^‍]]/
    NOTIFICATION_STRIP_RE = /[\p{Cc}\p{Cf}&&[^\n‍]]/
    # A CLI stderr line that is an NDJSON progress or diagnostic event
    # (dropped from `details`, never shown).
    PROGRESS_RE = /\A\s*\{\s*"type"\s*:\s*"(?:progress|diagnostic)"/
    # Look-alikes for the markup characters of a notification body.
    BODY_NEUTRAL = { '<' => "\u2039", '>' => "\u203A", '&' => "\uFF06" }.freeze
    # "://" with its slashes swapped for U+2044 FRACTION SLASH: visible, not a
    # format character, and no daemon URL pattern matches it.
    URL_DEFANG = ":\u2044\u2044"
    # The cap on a notification title or body, in chars.
    NOTIFICATION_MAX = 300
    # The cap on a failure's `details` list, in lines.
    DETAILS_MAX = 20
    # The most characters of an untrusted value a message repeats (Text.quote).
    ECHO_MAX = 40

    module_function

    # A pasted field value: the first line of `value`, valid UTF-8, control
    # and format characters removed (inner spaces kept: a folder path may
    # hold two), trimmed, at most `max` characters (cut, no ellipsis).
    def pasted(value, max)
      line = scrub(value.to_s).sub(/[\r\n].*/m, '')
      line.gsub(CONTROL_RE, '').strip[0, max]
    end

    # Valid UTF-8, no ANSI sequences, no control/format characters, single
    # spaces, at most `max` characters (with an ellipsis when cut).
    def clean(value, max = 200)
      s = scrub(value.to_s).gsub(ANSI_RE, '').gsub(CONTROL_RE, ' ').gsub(/[[:space:]]+/, ' ').strip
      truncate(s, max)
    end

    # The bytes of `value` read as UTF-8 (possibly invalid: argv under
    # LANG=C, child output). The one force_encoding in Shop.
    def as_utf8(value)
      value.to_s.dup.force_encoding(Encoding::UTF_8)
    end

    # Valid UTF-8: invalid bytes become "?".
    def scrub(value)
      as_utf8(value).scrub('?')
    end

    def truncate(s, max)
      return s if s.length <= max

      "#{s[0, max - 1]}…"
    end

    # The diagnostic lines of a CLI stderr tail: progress NDJSON dropped, the
    # rest cleaned; the last DETAILS_MAX non-empty lines of at most 200 chars.
    def details(tail)
      lines = scrub(tail).split(/\r?\n/).reject { |l| l.match?(PROGRESS_RE) }
      lines.map { |l| clean(l) }.reject(&:empty?).last(DETAILS_MAX)
    end

    # An untrusted value repeated inside a message: cleaned, at most
    # ECHO_MAX characters, in double quotes (so an empty or odd value is
    # still visible as one).
    def quote(value)
      %("#{clean(value, ECHO_MAX)}")
    end

    # A SystemCallError's own reason without the detail Ruby appends ("No
    # such file or directory @ rb_sysopen - /a/long/path" -> "no such file or
    # directory"): the caller says which path it was. Any other exception's
    # message as it is.
    def os_error(error)
      return error.message unless error.is_a?(SystemCallError)

      reason = error.message.split(/ @ | - /, 2).first.to_s
      reason.sub(/\A[A-Z](?=[a-z])/, &:downcase)
    end

    # Natural order: digit runs compare numerically, the rest case-insensitively.
    def natural_compare(a, b)
      ta = a.to_s.downcase.scan(/\d+|\D+/)
      tb = b.to_s.downcase.scan(/\d+|\D+/)
      ta.zip(tb).each do |x, y|
        return 1 if y.nil?

        cmp = if x.match?(/\A\d/) && y.match?(/\A\d/)
                [x.to_i, x.length] <=> [y.to_i, y.length]
              else
                x <=> y
              end
        return cmp unless cmp.zero?
      end
      ta.length <=> tb.length
    end

    # Notification text: line and paragraph separators become "\n", other
    # control characters are stripped except "\n" (and the zero width
    # joiner), at most `max` characters. With `neutralise: true` (the body,
    # which daemons read as markup) `< > &` become the look-alikes ‹ › ＆
    # after the cap, so no tag and no entity can form. Escaping is not
    # enough: Omarchy's daemon decodes entities up to three times before it
    # puts back b/i/u/s/em/strong and <a href>, so "&lt;a href=…&gt;" would
    # come back as a live link. In both the title and the body every "://"
    # becomes ":⁄⁄" (two U+2044 fraction slashes, same length, before the
    # cap): the daemon offers the first http(s) URL of either field as the
    # card's click target and linkifies bare URLs in the body, so a product
    # title or store name carrying "https://…" would make the normal click
    # on a Shop toast open that page.
    def notification(value, neutralise: false)
      s = scrub(value.to_s).gsub(ANSI_RE, '').gsub(/[\p{Zl}\p{Zp}]/, "\n").gsub(NOTIFICATION_STRIP_RE, '')
      s = truncate(s.gsub('://', URL_DEFANG), NOTIFICATION_MAX)
      neutralise ? s.gsub(/[<>&]/, BODY_NEUTRAL) : s
    end
  end
end
