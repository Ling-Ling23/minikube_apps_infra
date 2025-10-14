# Data sources - these fetch information at runtime

# Get the current git branch automatically
data "external" "git_info" {
  program = ["bash", "-c", "echo '{\"branch\":\"'$(git branch --show-current)'\"}'"]
}

# Local values for easier access
locals {
  current_git_branch = data.external.git_info.result.branch
}