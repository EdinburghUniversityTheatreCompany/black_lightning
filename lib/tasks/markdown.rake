require "#{Rails.root}/lib/tasks/logic/markdown_heading_fix"

namespace :markdown do
  # :nocov:
  desc "Insert the missing space after # in Markdown headings (##Foo -> ## Foo) and trim " \
       "decorative closing #s (## Foo## -> ## Foo). Dry-run by default; APPLY=1 to write. " \
       "STRIP_ALL=1 also trims a lone glued trailing # (e.g. C#). MODEL=News scopes to one " \
       "model; MAX_HEADING_LEN=120 tunes the length cap."
  task fix_heading_spaces: :environment do
    dry_run   = ENV["APPLY"].to_s !~ /\A(1|true|yes)\z/i
    strip_all = ENV["STRIP_ALL"].to_s =~ /\A(1|true|yes)\z/i
    only      = ENV["MODEL"].presence
    max_len   = ENV.fetch("MAX_HEADING_LEN", Tasks::Logic::MarkdownHeadingFix::MAX_HEADING_LEN.to_s).to_i

    Tasks::Logic::MarkdownHeadingFix.run(dry_run: dry_run, only: only, max_len: max_len, strip_all: strip_all)

    puts dry_run ? "\nDRY RUN — nothing written. Re-run with APPLY=1 to persist." : "\nApplied."
  end
  # :nocov:
end
