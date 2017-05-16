require "http/client"
require "emoji"
require "colorize"
require "option_parser"
require "yaml"
require "./models/github_repos"
require "./models/time_cache"

# OptionParser.parse! do |parser|
#   parser.banner = "Usage: shard [find | install] name"
#   parser.on("-u", "--upcase", "Upcases the sallute") { upcase = true }
#   parser.on("-t NAME", "--to=NAME", "Specifies the name to salute") { |name| destination = name }
#   parser.on("-h", "--help", "Show this help") { puts parser }
# end

SORT_OPTIONS = {"stars", "updated", "forks"}
REPOS_CACHE  = TimeCache(String, GithubRepos).new(30.minutes)

def headers
  headers = HTTP::Headers.new
  headers["User-Agent"] = "crystalshards-cli"
  headers
end

def crystal_repos(searchterm, sort)
  client = HTTP::Client.new("api.github.com", 443, true)
  response = client.get("/search/repositories?q=language:crystal+#{URI.escape(searchterm, true)}&per_page=200&sort=#{sort}", headers)
  GithubRepos.from_json(response.body)
end

# def filter(repos, filter)
#   filtered = repos.dup
#   filtered.items.select! { |item| matches_filter?(item, filter) }
#   filtered.total_count = filtered.items.size
#   filtered
# end

def fetch_sort(env)
  sort = env.params.query["sort"]?.try(&.to_s) || "stars"
  sort = "stars" unless SORT_OPTIONS.includes?(sort)
  sort
end

# def fetch_filter(env)
#   env.params.query["filter"]?.try(&.to_s.strip.downcase) || ""
# end

# private def matches_filter?(item : GithubRepo, filter : String)
#   item.name.downcase.includes?(filter) ||
#     item.description.try(&.downcase.includes? filter)
# end

def search(term)
  sort = "stars"
  # filter =
  # sort = fetch_sort(env)
  # filter = fetch_filter(env)
  #
  # env.response.content_type = "application/json"
  repos = REPOS_CACHE.fetch(sort) { crystal_repos(term, sort) }
  # repos = filter(repos, filter) unless filter.empty?
  puts "Found #{repos.total_count} results".colorize(:dark_gray)
  width = 2 + repos.items.map { |r| r.name.size + r.owner.login.size }.max
  repos.items.each do |repo|
    puts "  #{(repo.owner.login + '/' + repo.name).rjust(width, ' ').colorize(:yellow)} #{"(#{repo.watchers_count} stars)".colorize(:blue)} #{repo.description.to_s.strip}"
  end
end

class ShardFile
  YAML.mapping(
    name: String,
    version: String,
    author: String,
    dependencies: Hash(String, Hash(String, String))
  )
end

# def yaml_deconstruct(yaml)
#   root = yaml.is_a?(YAML::Any) ? yaml.raw : yaml
#   case true
#   when root.is_a?(Hash)
#     root = root.as(Hash)
#     root.each { |k, v| root[k.to_s] = yaml_deconstruct(v) }
#   when root.is_a?(Array)
#     root = root.as(Array)
#     root.each_with_index { |v, i| root[i] = yaml_deconstruct(v) }
#   when root.is_a?(String)
#     root = root.as(String)
#   else
#     puts root
#     puts typeof(root)
#     return root
#   end
#   root
# end

def install(name)
  user, project = name.split('/')
  yml = File.read("./shard.yml")

  deps = <<-DEPS
  dependencies:
    #{project}:
      github: #{name}
  DEPS

  if yml.includes?("dependencies:")
    yml = yml.sub("dependencies:", deps)
  else
    yml += "\n" + deps
  end
  # shardfile = ShardFile.from_yaml(yml)
  # deps = shardfile.dependencies
  # deps[project] = {"github" => name} unless deps[project]?
  # File.write("./shard.yml", shardfile.to_yaml)
  File.write("./shard.yml", yml)
  puts "Added #{name} to shard.yml"
  system("shards install")
end

unless (ARGV[0]? && ARGV[1]?)
  puts "Usage: shard search|install name"
  exit
end

command, name = ARGV
sort_by = "stars"

case command
when "search"
  search(name)
when "install"
  install(name)
else
  puts "Unknown command #{command}"
end
