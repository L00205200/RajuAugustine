# CloudFormation Lab - L00205200 Raju

This repository contains my submission for the CloudFormation lab. It covers two parts:

- **Part A1a – `templates/01-static-website.yaml`:** a static website stored in Amazon S3 and delivered through Amazon CloudFront.
- **Part A1b – `templates/02-three-tier.yaml`:** a three-tier architecture with a web tier, an application tier and a database tier.

Both stacks were deployed and tested in an AWS Academy Learner Lab account.

## Repository Structure

```
.github/workflows/validate.yml    Validation pipeline that runs on every pull request
templates/01-static-website.yaml  S3 bucket and CloudFront distribution (Part A1a)
templates/02-three-tier.yaml      VPC and the web, application and database tiers (Part A1b)
website/                          Static website content (HTML and CSS)
scripts/deploy-website.sh         Deploys the website stack and uploads website/
scripts/deploy-three-tier.sh      Deploys the three-tier stack
scripts/teardown.sh               Deletes both stacks
docs/screenshots/                 Evidence of successful deployment
```

## Part A1a - Static Website

### Overview

The page header displays my student number and name (L00205200 - Raju). The site content is kept in the `website/` folder. It is uploaded to an S3 bucket, and CloudFront acts as the public-facing web service.

Most tutorials make the bucket public and enable S3 static website hosting. This approach works, but it serves the site over HTTP only and allows anyone to read the bucket directly. I took a more secure approach:

- **Private bucket.** All public access is blocked, and only CloudFront can read from the bucket, through Origin Access Control (OAC).
- **HTTPS only.** CloudFront redirects HTTP requests to HTTPS. The AWS managed security headers policy is attached, which adds HSTS, X-Frame-Options and other protective headers.
- **Data protection.** The bucket has encryption and versioning enabled, and the bucket policy denies any request that is not made over HTTPS.

```
User --HTTPS--> CloudFront --(OAC)--> Private S3 bucket  <-- aws s3 sync website/
```

CloudFormation cannot upload files to a bucket on its own, so `scripts/deploy-website.sh` handles the full deployment in three steps:

1. Deploys the CloudFormation stack.
2. Uploads `website/` with `aws s3 sync`.
3. Invalidates the CloudFront cache so that changes are visible immediately.

Keeping the content in a separate folder means the HTML can be updated and redeployed without changing the template.

CloudFormation cannot delete a bucket that still contains objects, and versioning keeps previous versions as well. To handle this, the template includes a small Lambda-backed custom resource that empties the bucket when the stack is deleted, which reduces teardown to a single command. This approach follows the AWS guidance on using Lambda with infrastructure as code referenced in the brief.

### Deployment

```bash
./scripts/deploy-website.sh
```

The first deployment takes about five minutes, mainly while CloudFront propagates. The script prints the website URL when it finishes.

## Part A1b - Three-Tier Architecture

### Network Layout

The template creates a VPC across two Availability Zones with three sets of subnets:

- **Public subnets:** the internet-facing load balancer and the NAT gateway.
- **Application subnets (private):** the web servers, the internal load balancer and the application servers.
- **Database subnets (private):** the RDS database. These subnets have no route to the internet.

Request flow:

```
Internet
  -> Public ALB (port 80)
  -> Web tier: nginx, Auto Scaling group
  -> Internal ALB (reachable only from the web tier)
  -> Application tier: Python API on port 8080, Auto Scaling group
  -> Database tier: RDS MySQL 8.4 on port 3306
```

The web page includes a short script that calls `/api`. nginx forwards the request to the application tier, which checks whether it can connect to the database. When all tiers are connected correctly, the page displays `"database_reachable": true`. This provides a simple end-to-end test that the three tiers are communicating, rather than only confirming that each one deployed.

### Security

- **Layered security groups.** Each security group accepts traffic only from the tier directly in front of it. For example, the database accepts connections only from the application servers' security group, not from an IP range.
- **No SSH access.** Port 22 is not open anywhere and no key pairs are required. Instances can be accessed through AWS Systems Manager Session Manager when needed.
- **Managed credentials.** The database password is not stored in the template. Secrets Manager generates a random password, and the template retrieves it at deployment time with a `{{resolve:secretsmanager:...}}` dynamic reference. The password therefore never appears in the repository or the CloudFormation console.
- **Hardened instances.** IMDSv2 is enforced, and both the EBS volumes and the RDS storage are encrypted.

### Scalability and Availability

- **Auto Scaling.** The web and application tiers each run in an Auto Scaling group with a target tracking policy set to 60% CPU. ELB health checks are used, so any instance that stops responding is replaced automatically.
- **Environment sizing.** The `EnvironmentName` parameter controls the footprint. The default value, `lab`, runs one instance per tier and a single-AZ database. Setting it to `prod` enables Multi-AZ for RDS, turns on deletion protection and runs a minimum of two instances per tier.
- **Maintainability.** The AMI is not hardcoded. It is resolved from the SSM public parameter for the latest Amazon Linux 2023 image, so the template stays current. The database uses `DeletionPolicy: Snapshot`, so a final snapshot is retained if the stack is deleted.

**Design trade-off:** a single NAT gateway is used to reduce cost. A production deployment should use one NAT gateway per Availability Zone; otherwise, an outage in that zone would remove outbound internet access for all private subnets.

### Deployment

```bash
./scripts/deploy-three-tier.sh
```

Database creation is the slowest step and takes 10 to 15 minutes. After the stack completes, allow a few minutes for the instances to install nginx and pass their health checks, then open the URL printed by the script.

## IAM and Access Control

AWS Identity and Access Management (IAM) controls who and what can access each resource in this project. The design applies the concepts covered in the AWS Academy *Introduction to AWS IAM* lab: users, groups, roles, managed and inline policies, and the principle of least privilege.

### IAM Concepts Applied

| Concept | What it is | How it is used in this project |
|---|---|---|
| **IAM user** | An identity for one person, with long-term credentials such as a console password or access keys | No IAM users are created. Services authenticate with roles, so there are no access keys to store or rotate. |
| **IAM group** | A collection of users that share the same permissions | Not created by the templates. A recommended group structure for a team is described below. |
| **IAM role** | An identity with permissions that can be assumed by a person or service, using temporary credentials | The Lambda function and the EC2 instances each use a role. |
| **AWS managed policy** | A pre-built policy maintained by AWS that can be attached to many identities | `AWSLambdaBasicExecutionRole` (CloudWatch Logs) and `AmazonSSMManagedInstanceCore` (Session Manager access). |
| **Inline policy** | A policy embedded in a single user, group or role, typically for one-off permissions | `website-bucket-cleanup`, attached only to the cleanup Lambda role. |
| **Resource-based policy** | A policy attached to a resource rather than to an identity | The S3 bucket policy, which controls who can read the website bucket. |

### Roles Defined in the Templates

| Role | Used by | Permissions | Least-privilege measure |
|---|---|---|---|
| `CleanupRole` | Bucket cleanup Lambda function | Managed: `AWSLambdaBasicExecutionRole`. Inline: list, delete objects and delete object versions | The inline policy is scoped to this one bucket's ARN, not `*`. |
| `ServerRole` (via `ServerProfile`) | Web and application EC2 instances | Managed: `AmazonSSMManagedInstanceCore` | Grants Session Manager access only. The instances have no permissions to S3, RDS or other services. |

EC2 instances receive their role through an **instance profile**, and the role's temporary credentials are delivered through the instance metadata service. IMDSv2 is enforced on every instance, which protects these credentials against server-side request forgery attacks.

### Policy Structure Example

Each policy statement follows the **Effect**, **Action** and **Resource** structure. The inline policy for the cleanup Lambda function shows how the scope is limited:

```yaml
- Effect: Allow                                           # Allow or Deny
  Action: [s3:DeleteObject, s3:DeleteObjectVersion]       # Permitted API calls
  Resource: !Sub '${WebsiteBucket.Arn}/*'                 # This bucket only
```

The S3 bucket policy uses both effects:

- An **Allow** statement grants `s3:GetObject` to the CloudFront service. A `Condition` on `AWS:SourceArn` restricts it to this stack's distribution only.
- A **Deny** statement blocks every request not made over HTTPS. In IAM policy evaluation, an explicit Deny always overrides an Allow, so no other policy can bypass this rule.

### Recommended Team Access Model

The templates do not create users or groups, but in a team environment I would manage human access with groups rather than permissions attached to individual users, following the same pattern as the IAM lab:

| Group | Purpose | Example policy |
|---|---|---|
| `CFN-Deployers` | Deploy and update stacks through CloudFormation | Custom policy for CloudFormation, S3, CloudFront, EC2, ELB, RDS and Secrets Manager |
| `Support-ReadOnly` | View resources for troubleshooting without changing them | `ReadOnlyAccess` (AWS managed) |
| `DB-Admins` | Retrieve database credentials when required | Inline policy allowing `secretsmanager:GetSecretValue` on the database secret only |

Adding a new team member then only requires placing them in the correct group, and a permission change applied to the group takes effect for every member immediately.

### AWS Academy Learner Lab Restriction

Learner Lab does not permit the creation of IAM roles. To support both environments, each template includes an `IamMode` parameter:

- `learnerlab` (default): skips role creation and uses the pre-provisioned `LabRole` and `LabInstanceProfile`.
- `create`: provisions the dedicated least-privilege roles described above, for use in a standard AWS account.

The role resources use a CloudFormation `Condition`, so they are created only when `IamMode` is set to `create`. Note that `LabRole` is broader than the custom roles, so the `create` mode is the recommended option outside the lab.

All deployments were run from AWS CloudShell in `us-east-1`, which provides the AWS CLI with credentials already configured.

## Teardown

The NAT gateway, load balancers and RDS instance consume credits while running, so both stacks are deleted after testing:

```bash
./scripts/teardown.sh
```

## Part B - Tooling and Workflow

**Development environment.** I used VS Code with the CloudFormation Linter extension, which highlights errors during editing. It identified that `EngineVersion: '8.0'` is not a valid RDS value. I updated it to a specific 8.4 release, as MySQL 8.0 is approaching the end of standard support.

**Continuous integration.** A GitHub Actions workflow validates every pull request with three tools:

- `cfn-lint` checks the templates against the CloudFormation resource specification.
- `checkov` reports security and best-practice findings. It runs in soft-fail mode, so findings are reported for review without blocking the merge.
- `shellcheck` checks the deployment scripts for common errors.

**Script reliability.** The deployment scripts use `set -euo pipefail`, so they stop at the first error rather than leaving a partially completed deployment.

**Branching.** Each change was developed on a dedicated branch and merged through a pull request:
`feature/ci-lint`, `feature/s3-website`, `feature/website-content`, `feature/three-tier`, `feature/deploy-scripts`, `docs/readme`.

## Testing

| Test | Result |
|---|---|
| `cfn-lint templates/*.yaml` passes | |
| Website loads over HTTPS with "L00205200 - Raju" in the header | |
| Direct access to an S3 object URL returns 403 (bucket is private) | |
| A non-existent page (for example `/abc`) returns the custom 404 page | |
| Three-tier page displays `database_reachable: true` | |
| A terminated application instance is replaced by the Auto Scaling group | |
| `teardown.sh` deletes both stacks successfully | |

## Tutorials and LLM Usage

The brief permits the use of tutorials or an LLM for the basics, provided they are declared. The following resources were used:

- AWS documentation: [Lambda and infrastructure as code](https://docs.aws.amazon.com/lambda/latest/dg/foundation-iac.html), for the custom resource approach.
- Claude (Anthropic), to generate the baseline templates, website content and deployment scripts. Prompts used:
  - *"Create CloudFormation templates for an S3 static website with my L-number in the header and a three-tier architecture, following best practice."*
  - *"I have AWS Academy Learner Lab credits, give me the steps to create the website and three tier using the assignment, create the static website also."*

  Claude was also used to review and edit the wording of this README and the code comments.


