terraform {
  required_providers {
    gitea = {
      source = "go-gitea/gitea"
      version = "0.6.0"
    }
  }
}

provider "gitea" {
  base_url = var.gitea_url # optionally use GITEA_BASE_URL env var
  token    = var.gitea_token # optionally use GITEA_TOKEN env var

  # Username/Password authentication is mutally exclusive with token authentication
  # username = var.username # optionally use GITEA_USERNAME env var
  # password = var.password # optionally use GITEA_PASSWORD env var

  # A file containing the ca certificate to use in case ssl certificate is not from a standard chain
  cacert_file = var.cacert_file

  # If you are running a gitea instance with self signed TLS certificates
  # and you want to disable certificate validation you can deactivate it with this flag
  insecure = false
}

resource "gitea_repository" "homelab" {
  username     = "w4sp0"
  name         = "homelab"
  private      = true
  issue_labels = "Default"
  license      = "MIT"
  gitignores   = "Terraform"
}


resource "gitea_org" "test_org" {
  name = "test-org"
}

resource "gitea_repository" "org_repo" {
  username = gitea_org.test_org.name
  name = "org-test-repo"
}
