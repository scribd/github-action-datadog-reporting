require 'octokit'
require 'rubygems'
require 'dogapi'
require 'date'
require 'json'

def collect_metrics(workflow_run, jobs, tags)
  jobs.map{|job| collect_job_metrics(job, tags)}.compact + \
  collect_workflow_metrics(workflow_run, jobs, tags)
end

def collect_job_metrics(job, tags)
  return nil unless job["status"] == "completed"
  [
    "job_duration",
    job["completed_at"] - job["started_at"],
    tags + ["status:#{job["conclusion"]}", "name:#{job["name"]}"]
  ]
end

def collect_workflow_metrics(workflow_run, jobs, tags)
  start = workflow_run["run_started_at"]
  finish = jobs.max_by{|job| job["completed_at"]}["completed_at"]
  status = if jobs.any?{|job| job["conclusion"] == "cancelled"}
             "cancelled"
           elsif jobs.all?{|job| ["success", "skipped"].include? job["conclusion"]}
             "success"
           else
             "failure"
           end
  is_retry = workflow_run["run_attempt"] > 1
  [[
    "workflow_duration",
    finish - start,
    tags + ["status:#{status}","retry:#{is_retry}"]
  ]]
end

def submit_metrics(metrics, datadog_client, metric_prefix)
  datadog_client.batch_metrics do
    metrics.each do |metric, value, tags|
      metric = metric_prefix + metric
      puts "#{metric}, #{value}, #{tags}"
      datadog_client.emit_point(metric, value, :tags => tags, :type => 'gauge')
      datadog_client.emit_point(metric + ".count", 1, :tags => tags, :type => 'counter')
    end
  end
end

def prior_jobs(github_client, jobs)
  length = jobs[:total_count].to_i
  finished_jobs = jobs[:jobs].select{|job| !job["conclusion"].nil? }
  while length - jobs[:jobs].length > 0
    length -= jobs[:jobs].length
    jobs = github_client.get(github_client.last_response.rels[:next].href)
    finished_jobs += jobs[:jobs].select{|job| !job["conclusion"].nil? }
  end
  puts "Found #{finished_jobs.count} completed jobs to report out of #{jobs[:total_count]} total jobs"
  finished_jobs
end

def collect_merged_data(github_client, repo, teams)
  pr_info = github_client.pull_request(repo, ENV['PR_NUMBER'])
  base_branch = pr_info[:base][:ref]
  default_branch = pr_info[:base][:repo][:default_branch]
  
  # Calculate time to merge
  time_to_merge = pr_info["merged_at"] - pr_info["created_at"]
  
  # Calculate lines changed
  diff_size = pr_info["additions"] + pr_info["deletions"]
  
  # Calculate time from first review to merge
  first_review_time = first_review_creation_time(github_client, pr_info)
  time_from_first_review_to_merge = pr_info["merged_at"] - first_review_time

  tags = CUSTOM_TAGS + ["project:#{repo}", "default_branch:#{base_branch == default_branch}"]
  tags += teams.map{|team| "team:#{team}"} if teams && teams.count.positive?
  
  [
    ["time_to_merge", time_to_merge, tags],
    ["lines_changed", diff_size, tags],
    ["time_from_first_review_to_merge", time_from_first_review_to_merge, tags] # Adding time from first review to merge metric
  ]
end

def first_review_creation_time(github_client, pr_info)
  reviews = github_client.pull_request_reviews(pr_info[:base][:repo][:full_name], pr_info[:number])
  first_review = reviews.find { |review| review["state"] == "APPROVED" || review["state"] == "CHANGES_REQUESTED" }
  first_review.nil? ? pr_info["created_at"] : first_review["submitted_at"]
end

def collect_opened_data(github_client, repo, teams)
  pr_info = github_client.pull_request(repo, ENV['PR_NUMBER'])
  base_branch = pr_info[:base][:ref]
  default_branch = pr_info[:base][:repo][:default_branch]
  commits = github_client.get(pr_info["commits_url"])
  time_to_open = pr_info["created_at"] - commits.first["commit"]["committer"]["date"]
  tags = CUSTOM_TAGS + ["project:#{repo}", "default_branch:#{base_branch == default_branch}"]
  tags += teams.map{|team| "team:#{team}"} if teams && teams.count.positive?
  [
    ["time_to_open", time_to_open, tags]
  ]
end

def collect_duration_data(github_client, repo, run_id)
  run = github_client.get("repos/#{repo}/actions/runs/#{run_id}")
  workflow = github_client.get("repos/#{repo}/actions/workflows/#{run["workflow_id"]}")
  tags = CUSTOM_TAGS + ["workflow:#{workflow["name"]}", "project:#{repo}"]
  jobs = prior_jobs(github_client, github_client.get(run["jobs_url"]))
  branch = run["head_branch"]
  if TAGGED_BRANCHES != []
    tags += ["branch:#{TAGGED_BRANCHES.include?(branch) ? branch : "other" }"]
  end
  collect_metrics(run, jobs, tags)
end

def parse_array_input(arg)
  arg.nil? || arg == '' ? [] : JSON.parse(arg.strip)
end

TAGGED_BRANCHES = parse_array_input(ARGV[4])
CUSTOM_TAGS = parse_array_input(ARGV[5])

repo = ARGV[0].strip
run_id = ARGV[1].strip
metric_prefix = ARGV[2].strip
teams = parse_array_input(ARGV[3])
metric_prefix += "." unless metric_prefix.end_with?(".")
datadog_client = Dogapi::Client.new(ENV['DATADOG_API_KEY'])
datadog_client.datadog_host = ARGV[6].strip
github_client = Octokit::Client.new(:access_token => ENV['OCTOKIT_TOKEN'])

metrics = nil

case ENV['ACTION'].strip
when "closed"
  metrics = collect_merged_data(github_client, repo, teams)
when "opened"
  metrics = collect_opened_data(github_client, repo, teams)
when "job_metrics"
  metrics = collect_duration_data(github_client, repo, run_id)
end

submit_metrics(metrics, datadog_client, metric_prefix) if metrics
