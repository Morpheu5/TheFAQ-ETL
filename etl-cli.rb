#!/usr/bin/env ruby
# frozen_string_literal: true

require 'elasticsearch'
require 'git'
require 'psych'
require 'slop'
require 'tmpdir'

require_relative 'config/app'

def make_ref_html(ref, i)
  link = " [<a href=\"#{ref['url']}\">link</a>]" unless ref['url'].nil?
  date = ref['retrieved_on'].strftime('%-d %B %Y') unless ref['retrieved_on'].nil?
  retrieved_on = "Retrieved on: #{date}." unless date.nil?
  language = "Language: #{ref['lang']}" unless ref['lang'].nil? or ref['lang'].empty?
  "<li>[#{i}] #{ref['text']}#{link}. #{retrieved_on} #{language}</li>"
end

opts = Slop.parse do |o|
  o.string '-s', '--sha', 'The commit SHA that needs to be parsed'
  o.string '-r', '--repo', 'The git repository with content to parse'
  o.string '-e', '--elasticsearch-url', 'The full URL of your ElasticSearch instance'
end

git_dir = Dir.mktmpdir(['thefaq-', '-etl'])

content_repo = CONTENT_REPO || opts[:repo]
if content_repo.nil? or content_repo.empty?
  warn opts.to_s
  warn "\nMust specify a content repository."
  exit(-2)
end

es_url = ES_URL || opts[:elasticsearch_url]
if es_url.nil? or es_url.empty?
  warn opts.to_s
  warn "\nMust specify an ElasticSearch URL."
  exit(-3)
end
es = Elasticsearch::Client.new url: es_url, log: false

sha = opts[:sha] || ''
if File.directory?(content_repo)
  git_dir = content_repo
  Git.open(git_dir).checkout(sha) unless sha.empty?
else
  begin
    g = Git.clone(content_repo, git_dir)
    g.checkout(sha) unless sha.empty?
  rescue Git::GitExecuteError => e
    warn "An error occurred while cloning the git repo (#{content_repo}):\n  #{e}"
    exit(-1)
  end
end
sha = Git.open(git_dir).log[0].to_s if sha.empty?

files = Dir.glob(git_dir + '/content/**/*.md')
ref_regexp = /~~~yaml\s+references\n(.*?)~~~/m
contents = files.map do |file|
  file_bn = file.gsub(/^.*\/content\//, '').gsub('.md', '').gsub('/index', '').gsub('_', '-')
  index_page = file.match?(/index\.md$/)
  warn '>>> ' + file_bn + (index_page ? '/index' : '')

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
  
  title_re = /^# (.*)/
  title = content.match(title_re)[1] || ''
  warn '    Missing title' if title.empty?

  summary_re = /^# .+?\n+(.*)/m
  summary = content.match(summary_re)[1].split("\n")[0]
  warn '    Unable to generate summary' if summary.empty?

  warn ''

  {
    id: file_bn,
    index: index_page,
    title: title,
    summary: summary,
    content: content
  }
end

es_index = "#{sha}_content"
es.indices.delete index: es_index, ignore_unavailable: true
es.indices.create index: es_index

contents.each do |c|
  es.create index: es_index,
            type: 'doc',
            id: c[:id],
            body: c
end

begin
  es.indices.get_alias(name: 'current_content').keys.each do |index|
    es.indices.delete_alias index: index, name: 'current_content'
  end
rescue Elasticsearch::Transport::Transport::Errors::NotFound
  warn "Alias current_content not found. Continuing..."
end
es.indices.put_alias index: es_index, name: 'current_content'

Git.open(git_dir).checkout('master')


