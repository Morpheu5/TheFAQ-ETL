#!/usr/bin/env ruby
# frozen_string_literal: true

require 'psych'
require 'git'
require 'tmpdir'

require_relative 'config/app'

def make_ref_html(ref, i)
  link = " [<a href=\"#{ref['url']}\">link</a>]" unless ref['url'].nil?
  "<li>[#{i}] #{ref['text']}#{link}</li>"
end

git_dir = Dir.mktmpdir(['thefaq-', '-etl'])
content_repo = CONTENT_REPO

if File.directory?(content_repo)
  git_dir = content_repo
else
  begin
    Git.clone(content_repo, git_dir)
  rescue Git::GitExecuteError => e
    warn "An error occurred while cloning the git repo (#{content_repo}):\n  #{e}"
    exit(-1)
  end
end

files = Dir.glob(git_dir + '/content/**/*.md')

ref_regexp = /~~~yaml references\n(.*)~~~/m

contents = files.map do |file|
  content = File.read(file)
  refs_yaml = content.scan(ref_regexp).flatten.join('\n').strip
  refs = Psych.load(refs_yaml) || {}
  ref_keys = refs.keys.sort
  refs_idx = ref_keys.each_with_index.map do |v, i|
    [v, "<a href=\"##{v}\">#{i+1}</a>"]
  end.to_h
  refs_list = ref_keys.each_with_index.map { |v, i| make_ref_html(refs[v], i+1) }
  content = content.gsub(ref_regexp, '').gsub(/(#{ref_keys.join('|')})/, refs_idx).strip
  content = content + "\n\n---\n\n## References\n\n<ul>\n\t" + refs_list.join("\n\t") + "\n</ul>" unless refs_list.empty?

  content
end

puts contents