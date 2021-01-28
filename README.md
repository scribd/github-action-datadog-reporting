# Datadog Velocity Metrics for GitHub and GitHub Actions

This action integrates into pre-existing Datadog and GitHub Actions workflows, and reports metrics to Datadog based on job and workflow performance.

## Features

### Capture GitHub Action Job and Workflow metrics

One of the features of this action is to report metrics on job duration and workflow duration in GitHub Actions. The metrics tracked are:

- Job duration, 1 metric submitted per job in a workflow that uses the action
- Workflow duration, 1 metric submitted per workflow that uses the action.

The following represents example metrics submitted for job duration and workflow duration

Metric name: `<prefix>.job_duration`

Metric value: `151.0`

tags: 
```
{
  workflow: "My workflow name",
  project: "scribd/my_repository",
  status: "success",
  name: "My-job-name",
}
```

Metric name: `<prefix>.workflow_duration`

Metric value: `1223.0`

tags: 
```
{
  workflow: "My workflow name",
  project: "scribd/my_repository",
  status: "success",
}
```

### Capture Development Velocity Metrics

This action also provides the capability to establish a separate workflow that tracks useful developer velocity metrics. Currently the metrics tracked are 

- Time to merge per pull request (Time difference between PR open and merge), reported on PR merged.
- Lines changed per pull request, reported on PR merged.
- Time to open a pull request (Time difference between first commit and PR open), reported on PR open.

The following represents example metrics for time to merge, lines changed and time to open

Metric name: `<prefix>.time_to_merge`

Metric value: `897.0`

tags: `{project: "scribd/my_repository"}`



Metric name: `<prefix>.lines_changed`

Metric value: `123.0`

tags: `{project: "scribd/my_repository"}`



Metric name: `<prefix>.time_to_open`

Metric value: `389.0`

tags: `{project: "scribd/my_repository"}`



## Inputs

### datadog-metric-prefix

A prefix for all of the datadog metrics. If multiple projects in your organization have the same job names then using different metrics for different projects will allow easy separation of the metrics.

### metrics-type

Internal configuration for the action. `job_metrics` should be passed for capturing job_duration and workflow durations, while `velocity` should be passed when used in a `Velocity Workflow` as seen below.

## Enviornment Variables

The following two secrets are required to be added to your GitHub settings for access to Datadog and GitHub during the workflow run.

### OCTOKIT_TOKEN

This token allows the action to request information about the workflow run from GitHub and enables calculating the relevant metrics. You can learn how to generate a personal access token (PAT) here: https://docs.github.com/en/github/authenticating-to-github/creating-a-personal-access-token

The only permission required for the PAT is `repo`

### DATADOG_TOKEN

This token allows the action to submit the metrics to datadog. You can learn how to generate an API token from Datadog here: https://docs.datadoghq.com/account_management/api-app-keys/

## Examples

### Capture GitHub Action Job and Workflow metrics

To capture job performance of an existing workflow, this action *must* run after all jobs, otherwise it will not report performance for jobs that have not completed at the time of the action running. For example, if there were 3 jobs in a workflow, and job2 `needs` job1, then the below configuration will ensure that the workflow and all jobs are properly captured.

The metrics that are captured for GitHub Action jobs are:

- `{datadog-metric-prefix}.job_duration`
  - Tagged with job status, job name, workflow name and repository.
- `{datadog-metric-prefix}.workflow_duration`
  - Tagged with workflow status, workflow name, and repository.

```
metrics:
    needs: [job2, job3]
    runs-on: ubuntu-latest
    name: Datadog reports
    if: ${{ always() }}
    steps:
    - uses: actions/setup-ruby@v1
      with:
        ruby-version: 2.6
    - uses: scribd/github-action-datadog-reporting@v1
      with:
        datadog-metric-prefix: 'project.prefix'
        metrics-type: 'job_metrics'
      env:
        DATADOG_API_KEY: ${{ secrets.DATADOG_API_KEY }}
        OCTOKIT_TOKEN: ${{ secrets.OCTOKIT_TOKEN }}
```

### Capture Development Velocity Metrics

The following example can be placed into a workflow file to report the Development Velocity metrics:

- `{datadog-metric-prefix}.time_to_open`
- `{datadog-metric-prefix}.time_to_merge`
- `{datadog-metric-prefix}.lines_changed`

```
name: Velocity Workflow
on:
  pull_request:
    types: [opened, closed]
jobs:
  metrics:
    if: |
      (github.event.action == 'closed' &&
      github.event.pull_request.merged == true) ||
      github.event.action == 'opened'
    name: Track merge request activity
    runs-on: ubuntu-latest
    steps:
      - uses: actions/setup-ruby@v1
        with:
          ruby-version: 2.6
      - id: datadog-metrics
        uses: scribd/github-action-datadog-reporting@v1
        with:
          datadog-metric-prefix: 'project.prefix'
          metrics-type: 'velocity'
        env:
          DATADOG_API_KEY: ${{ secrets.DATADOG_API_KEY }}
          OCTOKIT_TOKEN: ${{ secrets.OCTOKIT_TOKEN }}
```

## License

This project is released under the [MIT License](LICENSE)

## Code of Conduct

See [our code of conduct](CODE_OF_CONDUCT.md)