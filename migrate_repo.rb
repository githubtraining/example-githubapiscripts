require "json"
require "typhoeus"
require "pp"

# MigrateRepo usage instructions:
#
# The way this is used at REDACTEDBYREQUEST for migrating from GitHub to GHE is by
# creating a separate organization with no members called "migration",
# adding that as the target organization, and then once the migration
# has finished, moving it over to the intended location.
#
# The reason why we do it this way is so that people who are auto-
# subscribed to the intended organization are not spammed by potentially
# thousands of comments in the source repository.
#
# The sleep time is arbitrarily chosen based on empirical evidence that
# lower times cause huge backups in resque jobs.
#
# Generally speaking, the source api host will be api.github.com, the
# source host will be github.com and the source prefix will be empty.
#
# The target api host and the target host will be your GHE deployment
# domain. Your target prefix will be "/api/v3".
#
# There is a known failure case on comments where the basis commit was
# lost in a force push. In this case, it will say "Server Error" and
# will move on to the next comment. This is unfortunately expected in
# many circumstances. Any write requests to the target will be spit
# out at the end of the run and you can choose to keep the output for
# posterity or to discard it if you really don't care.
#
# Don't use this tool on existing repos. It is intended to be used
# on repos that are moved over for the first time from another
# GitHub organization.

class MigrateRepo
  HOOK_URLS = []

  SOURCE_ORGANIZATION = ""
  SOURCE_API_HOST = ""
  SOURCE_HOST = ""
  SOURCE_PREFIX = ""

  TARGET_ORGANIZATION = ""
  TARGET_API_HOST = ""
  TARGET_HOST = ""
  TARGET_PREFIX = ""

  SLEEP_TIME = 1

  def self.migrate(source_auth_token, target_auth_token, repo)
    source = GithubHost.new(
      :host => SOURCE_HOST,
      :api_host => SOURCE_API_HOST,
      :prefix => SOURCE_PREFIX,
      :token => source_auth_token,
      :org => SOURCE_ORGANIZATION,
      :repo => repo,
    )
    target = GithubHost.new(
      :host => TARGET_HOST,
      :api_host => TARGET_API_HOST,
      :prefix => TARGET_PREFIX,
      :token => target_auth_token,
      :org => TARGET_ORGANIZATION,
      :repo => repo,
    )
    old_repo = source.request(
      "/repos/#{SOURCE_ORGANIZATION}/#{repo}",
      :method => :get,
    )

    # Create the repo and add hooks, content
    self.create_repo(target, old_repo)
    self.add_hooks(target, HOOK_URLS)
    self.push_content(source, target)

    # Create a mapping of all pull requests from number to content
    pulls = self.pull_requests(source)
    pull_map = pulls.inject({}){|h, p| h[p["number"]] = p; h}

    self.issues(source).each do |old_issue|
      puts "Processing issue #{old_issue["number"]}"

      # Create the issue
      issue = self.add_issue(target, old_issue)

      # Check to see if it has a pull request
      has_pull = pull_map.include?(old_issue["number"])

      # Get all comments in the issue
      comments = self.comments(source, old_issue, has_pull)

      # Add the pull request iff one exists on the original issue
      if has_pull
        self.add_pull(target, pull_map[old_issue["number"]], issue)
      end

      # Add each comment
      comments.each do |comment|
        if comment["commit_id"]
          # A commit id means that this is a PR comment
          self.add_pull_comment(target, issue, comment)
        else
          # This is an issue comment
          self.add_issue_comment(target, issue, comment)
        end

        # Sleep for a little bit after each comment.
        # This is to reduce resque burden and resolve random other issues
        # around out-of-order comments that have been seen without this.
        sleep(SLEEP_TIME)
      end

      # Finally, close the issue if the original one was already closed
      if old_issue["state"] != "open"
        self.close_issue(target, issue, old_issue["state"])
      end
    end

    pp target.failures
  end

  def self.create_repo(target, old_repo)
    target.request(
      "/orgs/#{target.org}/repos",
      :method => :post,
      :body => {
        "name" => target.repo,
        "description" => old_repo["description"],
        "private" => true,
      }.to_json,
    )
  end

  def self.add_hooks(target, hooks)
    HOOK_URLS.each do |hook_url|
      target.request(
        "/repos/#{target.org}/#{target.repo}/hooks",
        :method => :post,
        :body => {
          "name" => "web",
          "active" => true,
          "config" => {
            "url" => hook_url,
            "content_type" => "json",
          },
        }.to_json,
      )
    end
  end

  def self.push_content(source, target)
    Dir.mktmpdir(source.repo) do |dir|
      `git clone --mirror git@#{source.host}:#{source.org}/#{source.repo}.git #{dir}`
      `git --git-dir=#{dir} remote add target git@#{target.host}:#{target.org}/#{target.repo}.git`
      `git --git-dir=#{dir} push --all target`
      `git --git-dir=#{dir} push --tags target`
    end
  end

  def self.add_issue(target, old_issue)
    issue = target.request(
      "/repos/#{target.org}/#{target.repo}/issues",
      :method => :post,
      :body => {
        :title => old_issue["title"],
        :body => annotated_body(old_issue),
      }.to_json,
    )
  end

  def self.close_issue(target, issue, state)
    # Close the issue
    target.request(
      "/repos/#{target.org}/#{target.repo}/issues/#{issue["number"]}",
      :method => :patch,
      :body => {
        :state => state,
      }.to_json,
    )
  end

  def self.add_issue_comment(target, issue, comment)
    target.request(
      "/repos/#{target.org}/#{target.repo}/issues/#{issue["number"]}/comments",
      :method => :post,
      :body => {
        :body => annotated_body(comment),
      }.to_json,
    )
  end

  def self.add_pull(target, old_pull, new_issue)
    if old_pull["state"] == "open"
      # If the PR is open, assume the refs are present
      base = old_pull["base"]["ref"]
      head = old_pull["head"]["ref"]
    else
      # If the PR is closed, fall back to SHA
      base = old_pull["base"]["sha"]
      head = old_pull["head"]["sha"]
    end
    pull = target.request(
      "/repos/#{target.org}/#{target.repo}/pulls",
      :method => :post,
      :body => {
        :issue => new_issue["number"],
        :base => base,
        :head => head,
      }.to_json,
    )
  end

  def self.add_pull_comment(target, issue, comment)
    target.request(
      "/repos/#{target.org}/#{target.repo}/pulls/#{issue["number"]}/comments",
      :method => :post,
      :body => {
        :body => annotated_body(comment),
        :commit_id => comment["original_commit_id"],
        :path => comment["path"],
        :position => comment["original_position"],
      }.to_json,
    )
  end

  def self.annotated_body(original)
    author = original["user"]["login"]
    timestamp = original["created_at"]
    body = original["body"]

    "Originally posted by #{author} at #{timestamp}:\n\n#{body}"
  end

  def self.issues(source)
    open = source.get_all(
      "/repos/#{source.org}/#{source.repo}/issues",
      :params => {
        :state => "open",
      },
    )
    closed = source.get_all(
      "/repos/#{source.org}/#{source.repo}/issues",
      :params => {
        :state => "closed",
      },
    )
    (open + closed).sort{|a, b| a["created_at"] <=> b["created_at"]}
  end

  def self.pull_requests(source)
    open = source.get_all(
      "/repos/#{source.org}/#{source.repo}/pulls",
      :params => {
        :state => "open",
      },
    )
    closed = source.get_all(
      "/repos/#{source.org}/#{source.repo}/pulls",
      :params => {
        :state => "closed",
      },
    )
    (open + closed).sort{|a, b| a["created_at"] <=> b["created_at"]}
  end

  def self.comments(source, issue, has_pull)
    comments = source.get_all(
      "/repos/#{source.org}/#{source.repo}/issues/#{issue["number"]}/comments",
      :params => {
        :sort => 'created',
      },
    )
    if has_pull
      comments += source.get_all(
        "/repos/#{source.org}/#{source.repo}/pulls/#{issue["number"]}/comments",
        :params => {
          :sort => 'created',
        },
      )
    end
    comments.sort{|a, b| a["created_at"] <=> b["created_at"]}
  end

  class GithubHost
    attr_reader :host, :org, :failures, :repo

    def initialize(options = {})
      @auth_token = options[:token]
      @api_host = options[:api_host]
      @host = options[:host]
      @prefix = options[:prefix]
      @org = options[:org]
      @repo = options[:repo]
      @failures = []
    end

    def request(path, options = {})
      tries = 0
      response = nil
      while tries <= 3
        tries += 1
        options[:headers] = {"Authorization" => "token #{@auth_token}"}
        request = Typhoeus::Request.new(
            "https://#{@api_host}#{@prefix}#{path}",
           options,
        )
        response = request.run
        if response.code < 300
          return response.body.empty? ? "" : JSON.parse(response.body)
        end
      end
      puts "Error: #{response.body}"
      @failures << [path, options, response.code]
      nil
    end

    def get_all(path, options = {})
      page = 1
      all_items = []
      while true
        items = request(
          path,
          :method => :get,
          :params => options[:params].merge({:page => page}),
        )
        break if items.empty?
        all_items += items
        page += 1
      end
      all_items
    end
  end
end

if ARGV.length < 3
  puts "ruby migrate_repo.rb <source_auth_token> <target_auth_token> <repo_name>"
else
  MigrateRepo.migrate(ARGV[0], ARGV[1], ARGV[2])
end
