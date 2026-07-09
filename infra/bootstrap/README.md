# Bootstrap

This directory creates the S3 bucket used as the Terraform remote state backend
for all other infrastructure directories (`global/`, `envs/staging/`, `envs/production/`).

## One-time apply

This directory uses **local state** intentionally — it can't use remote state
before the remote state bucket exists. Apply it once:

```bash
cd infra/bootstrap
terraform init
terraform apply -var="state_bucket_name=echo-terraform-state-382724554857"
```

Once the bucket is created, commit the `terraform.tfstate` file (it is tiny and
contains only the S3 bucket resource) **or** leave it in place on the machine
that ran the bootstrap. Do not lose it — without it Terraform cannot manage the
bucket itself. Consider checking it into a secure location (e.g. 1Password or
a restricted S3 path).

## What is created

- S3 bucket `echo-terraform-state-382724554857`
  - Versioning enabled
  - SSE-S3 (AES256) server-side encryption
  - Public access fully blocked
  - Noncurrent version expiration: 90 days

## Backend configuration used by other modules

```hcl
terraform {
  backend "s3" {
    bucket = "echo-terraform-state-382724554857"
    key    = "<module>/terraform.tfstate"
    region = "us-east-1"
  }
}
```

State locking: Terraform 1.9+ supports native S3 locking (`use_lockfile = true`)
without a DynamoDB table. All modules in this repo enable it.
