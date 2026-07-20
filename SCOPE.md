# terraform-aws-ssm — SCOPE

Composite **management** module for AWS Systems Manager (SSM) core primitives —
Parameter Store, Documents, State Manager Associations, Patch Manager
(baseline + patch group), and a Maintenance Window with its targets/tasks. It
is also Casey's recommended vehicle for wiring Session Manager as the default,
SSH-free path to EC2 access, secure by default with SecureString-backed
Parameter Store values.

- **Module type:** Composite
- **Primary resource (keystone):** `aws_ssm_parameter.this`

## In-scope resources

The module manages **all** of the following (allow-list):

- `aws_ssm_parameter` — keystone; Parameter Store values (`for_each` over a
  caller-supplied map, since a module frequently manages several parameters)
- `aws_ssm_document` — Command / Automation / Session / Policy documents
- `aws_ssm_association` — State Manager associations binding a document to
  targets on a schedule
- `aws_ssm_patch_baseline` — Patch Manager baseline (approval rules / filters)
- `aws_ssm_patch_group` — registers a patch group name against a baseline
- `aws_ssm_maintenance_window` — scheduled maintenance window
- `aws_ssm_maintenance_window_target` — target registration for a window
  (**correction/addition** — see Provider gotchas; a window alone runs no
  tasks)
- `aws_ssm_maintenance_window_task` — task registration for a window
  (**correction/addition** — same reason)

> **Correction to starting brief:** the brief listed only
> `aws_ssm_maintenance_window`, but a maintenance window with no registered
> targets/tasks does nothing — Patch Manager's own quick-setup pattern
> registers a `RUN_COMMAND` task (`AWS-RunPatchBaseline`) against a window
> target. `aws_ssm_maintenance_window_target` and
> `aws_ssm_maintenance_window_task` are added to in-scope so the maintenance
> window composite is actually functional, not just a shell resource.

## Out-of-scope resources (consumed by reference)

Referenced by `arn`/`id`, never created here:

- **KMS CMK** for `SecureString` encryption — supplied by `terraform-aws-kms`
  via `kms_key_id` (accepts a key ID or ARN). Defaulting to `null` uses the
  AWS-managed `alias/aws/ssm` key.
- **IAM instance profile / role** granting `AmazonSSMManagedInstanceCore` (or
  equivalent least-privilege policy) to EC2 targets — owned by
  `terraform-aws-iam-role` (+ `terraform-aws-iam-policy`) and consumed by
  `terraform-aws-ec2-instance` as `iam_instance_profile`. This module does **not**
  create the instance profile; it documents the requirement (see the dedicated
  note below) because Session Manager access depends on it.
- **EC2 instances / Auto Scaling Groups** targeted by associations, patch
  groups, and maintenance windows — referenced by instance ID or tag key/value
  only, owned by `terraform-aws-ec2-instance` / `terraform-aws-autoscaling-group`.
- **S3 bucket** for association/maintenance-window command output logging —
  referenced by name/ARN from `terraform-aws-s3-bucket`.
- **SNS topic** for maintenance-window task notifications — referenced by ARN
  from `terraform-aws-sns` (Phase 2).
- **CloudWatch Log Group** for Run Command output — referenced by name from
  `terraform-aws-cloudwatch-log-group`.
- **Lambda functions / Step Functions state machines** invoked as maintenance
  window task targets — referenced by ARN only.
- **Service role for maintenance window tasks** (`service_role_arn`) — IAM
  role ARN from `terraform-aws-iam-role`; if omitted, AWS falls back to (and
  auto-creates, if absent) the SSM service-linked role.

## Consumes

| Input | Type | Source module |
|---|---|---|
| `kms_key_id` | `string` (KMS key ID or ARN, optional) | `terraform-aws-kms` |
| `iam_instance_profile` (documentation only — not a module variable) | ARN/name | `terraform-aws-iam-role` → `terraform-aws-ec2-instance` |
| `output_s3_bucket_name` (per-association / per-task, optional) | `string` | `terraform-aws-s3-bucket` |
| `notification_sns_arn` (per maintenance-window task, optional) | `string` | `terraform-aws-sns` (Phase 2) |
| `service_role_arn` (per maintenance-window task, optional) | `string` | `terraform-aws-iam-role` |
| `cloudwatch_log_group_name` (per maintenance-window task, optional) | `string` | `terraform-aws-cloudwatch-log-group` |

## Required IAM permissions

Least-privilege actions the Terraform identity needs:

| Action | Required for |
|---|---|
| `ssm:PutParameter`, `ssm:DeleteParameter`, `ssm:GetParameter`, `ssm:GetParameters`, `ssm:DescribeParameters`, `ssm:AddTagsToResource`, `ssm:RemoveTagsFromResource` | Parameter Store lifecycle + tagging |
| `kms:Decrypt`, `kms:GenerateDataKey`, `kms:DescribeKey` | Reading/writing `SecureString` values encrypted under a CMK (grant is on the **KMS key policy**, supplied by `terraform-aws-kms`) |
| `ssm:CreateDocument`, `ssm:DeleteDocument`, `ssm:DescribeDocument`, `ssm:UpdateDocument`, `ssm:UpdateDocumentDefaultVersion`, `ssm:ModifyDocumentPermission` | Document lifecycle + version management + sharing |
| `ssm:CreateAssociation`, `ssm:DeleteAssociation`, `ssm:DescribeAssociation`, `ssm:UpdateAssociation` | State Manager association lifecycle |
| `ssm:CreatePatchBaseline`, `ssm:DeletePatchBaseline`, `ssm:GetPatchBaseline`, `ssm:UpdatePatchBaseline` | Patch baseline lifecycle |
| `ssm:RegisterPatchBaselineForPatchGroup`, `ssm:DeregisterPatchBaselineForPatchGroup`, `ssm:GetPatchBaselineForPatchGroup` | Patch group registration |
| `ssm:CreateMaintenanceWindow`, `ssm:DeleteMaintenanceWindow`, `ssm:GetMaintenanceWindow`, `ssm:UpdateMaintenanceWindow` | Maintenance window lifecycle |
| `ssm:RegisterTargetWithMaintenanceWindow`, `ssm:DeregisterTargetFromMaintenanceWindow`, `ssm:GetMaintenanceWindowTarget` | Maintenance window target registration |
| `ssm:RegisterTaskWithMaintenanceWindow`, `ssm:DeregisterTaskFromMaintenanceWindow`, `ssm:GetMaintenanceWindowTask`, `ssm:UpdateMaintenanceWindowTask` | Maintenance window task registration |
| `ssm:AddTagsToResource`, `ssm:RemoveTagsFromResource`, `ssm:ListTagsForResource` | Tagging across all SSM resource types (Parameter, Document, PatchBaseline, MaintenanceWindow) |
| `iam:PassRole` | Passing `service_role_arn` to a maintenance window task, or an association's automation execution role — restrict to the specific role ARN(s), never `*` |
| `iam:CreateServiceLinkedRole` | Only if the account has never used Patch Manager / maintenance window tasks before and no `service_role_arn` is supplied — AWS auto-creates `AWSServiceRoleForAmazonSSM` on first use |

## AWS Prerequisites

- **No service-linked role required** to create the core resources in this
  module (`aws_ssm_parameter`, `aws_ssm_document`). Maintenance window tasks
  that omit `service_role_arn` cause AWS to auto-create the
  `AWSServiceRoleForAmazonSSM` service-linked role on first use — this is a
  one-time, account-level, implicit side effect worth calling out in change
  review.
- **Session Manager / managed-node prerequisites (the actual gate on whether
  associations, patch baselines, and maintenance windows can target an
  instance at all):**
  - The **SSM Agent** must be installed and running on the target EC2
    instance (preinstalled on Amazon Linux 2/2023, Ubuntu, and Windows AMIs
    published by AWS; must be installed manually on custom/older AMIs).
  - The instance needs **network reachability to the SSM, SSM Messages, and
    EC2 Messages endpoints** — either public egress (NAT/IGW) or VPC
    interface endpoints for `com.amazonaws.<region>.ssm`,
    `com.amazonaws.<region>.ssmmessages`, and
    `com.amazonaws.<region>.ec2messages` (`terraform-aws-vpc-endpoint`) for
    fully private subnets.
  - The instance needs **IAM permission to call SSM** via one of two paths:
    1. **Default Host Management Configuration** (account/Region-level,
       via the AWS-managed `AmazonSSMManagedEC2InstanceDefaultPolicy` bound
       to the default `AWSSystemsManagerDefaultEC2InstanceManagementRole`
       IAM role) — the newer, no-per-instance-role option; requires no
       instance profile at all once activated for the account/Region. Gated
       on every managed instance running **IMDSv2** and **SSM Agent
       >= 3.2.582.0**; activating it requires `iam:PassRole` on that default
       role.
    2. **Instance profile** attached to the EC2 instance carrying the
       AWS-managed policy **`AmazonSSMManagedInstanceCore`** (or a
       narrower custom policy covering the same core SSM actions) — the
       traditional, per-instance-role path and the one this module's
       Session Manager example wires explicitly. See the dedicated note
       below.
  - **Hybrid/on-premises nodes** use a hybrid activation's IAM service role
    instead of an instance profile.
- **Patch Manager quotas/behavior:** a patch baseline supports up to 10
  `approval_rule` blocks and 4 `global_filter` blocks; at least one of
  `approved_patches` or `approval_rule` must be set. `operating_system`
  defaults to `WINDOWS` in the provider — this module defaults it explicitly
  to avoid surprising non-Windows callers (see Provider gotchas).
- **Maintenance window quotas:** AWS enforces a maximum of **5 concurrently
  running maintenance windows** account-wide (soft, raiseable) plus a bounded
  number of registered targets/tasks per window; `cutoff` must be less than
  `duration` (enforced by this module's variable validation).
- **Parameter Store tiers/quotas:** `Standard` tier parameters are limited to
  4 KB and are free; `Advanced` tier raises the value size to 8 KB and adds a
  per-parameter monthly charge plus enables parameter policies (not modeled
  in this module's v1). `Intelligent-Tiering` auto-selects Standard/Advanced.
  Total parameter count is a soft, raiseable account quota.
- **Region:** standard provider inheritance — no `region` variable in this
  module (SSM is not one of the CloudFront/WAFv2/ACM us-east-1 globals).

### Session Manager IAM policy — dedicated note for `terraform-aws-ec2-instance`

Casey's standardizes on **AWS Systems Manager Session Manager** as the default
method for interactive EC2 access, in preference to SSH with distributed key
pairs and open port 22 — this eliminates inbound security-group rules,
long-lived SSH keys, and bastion hosts entirely, which materially reduces the
attack surface for NPI-adjacent workloads. This module does not create the
instance profile itself (that is `terraform-aws-iam-role`'s job) but every
EC2-facing example in this module's README wires the following pattern so the
recommendation is visible at the point of use:

1. `terraform-aws-iam-role` creates an EC2-trusted role with the AWS-managed
   policy **`AmazonSSMManagedInstanceCore`** attached (covers
   `ssmmessages:*`, `ec2messages:*`, and the minimum `ssm:UpdateInstance*` /
   `ssm:ListAssociations` / `ssm:GetDocument` actions the agent needs to
   register and poll for work) plus, if instance-level SSM parameter or KMS
   access is required, a scoped inline policy — never attach broader
   `AmazonSSMFullAccess`.
2. `terraform-aws-iam-role` (or a paired `terraform-aws-iam-role` call) wraps the
   role in an `aws_iam_instance_profile`.
3. `terraform-aws-ec2-instance` consumes the instance profile **name** via its
   `iam_instance_profile` argument.
4. This module (`terraform-aws-ssm`) then targets that instance (by ID or tag)
   with `aws_ssm_association` / patch group / maintenance window resources.

Callers on newer accounts may instead enable **Default Host Management
Configuration** at the account level (no per-instance profile needed), but
the per-instance-profile pattern above remains the explicit, auditable
default this library recommends for regulated workloads because it keeps the
permission grant scoped and visible in the Terraform plan for the specific
instance/role, rather than an implicit account-wide default.

## Emits

| Output | Description | Consumed by |
|---|---|---|
| `id` | Map of parameter name → parameter `id` (the parameter name) for every entry in `var.parameters` | Application config lookups, `terraform-aws-ecs-service` (env/secrets references), `terraform-aws-lambda` |
| `arn` | Map of parameter name → parameter ARN | `terraform-aws-iam-policy` (scoping `ssm:GetParameter` resource ARNs), `terraform-aws-ecs-service` (`valueFrom` for secrets) |
| `name` | Map of parameter name → parameter name (identical to key, echoed for symmetry with other modules' `name` output) | Documentation / cross-references |
| `version` | Map of parameter name → current parameter version (increments on every value update) | Drift detection, audit |
| `tags_all` | Map of parameter name → merged tags (resource tags over provider `default_tags`) | Governance / audit |
| `document_ids` | Map of document key → document `id` (the document name) | CLI/console cross-reference |
| `document_arns` | Map of document key → document ARN | `aws_ssm_association.name`, `terraform-aws-ec2-instance` user-data bootstrapping references |
| `document_names` | Map of document key → document name | `aws_ssm_association`, CLI/console cross-reference |
| `document_tags_all` | Map of document key → merged tags | Governance / audit |
| `association_ids` | Map of association key → `association_id` | Audit / drift-detection references |
| `association_arns` | Map of association key → association ARN | Audit / cross-resource reference |
| `association_tags_all` | Map of association key → merged tags | Governance / audit |
| `patch_baseline_ids` / `patch_baseline_arns` | Map of baseline key → ID / ARN | `aws_ssm_patch_group` registration, Patch Manager console cross-reference |
| `patch_baseline_tags_all` | Map of baseline key → merged tags | Governance / audit |
| `patch_group_ids` | Map of patch-group key → composite id (`"<patch_group>,<baseline_id>"`) | Audit — `aws_ssm_patch_group` is not taggable and has no ARN |
| `maintenance_window_ids` | Map of window key → `id` | `aws_ssm_maintenance_window_target` / `_task`, `terraform-aws-cloudwatch-alarm` (window compliance) — no ARN attribute exposed by this resource |
| `maintenance_window_tags_all` | Map of window key → merged tags | Governance / audit |
| `maintenance_window_target_ids` | Map of target key → maintenance window target `id` | Wiring into `maintenance_window_tasks[*].targets` (`WindowTargetIds`) — not taggable, no ARN |
| `maintenance_window_task_ids` | Map of task key → maintenance window task `id` | Audit / drift-detection references |
| `maintenance_window_task_arns` | Map of task key → maintenance window task ARN | Audit — not taggable despite exposing an ARN |

## Provider gotchas

- **`aws_ssm_parameter.value` is always sensitive in plan output**, regardless
  of `type` — `String` and `StringList` values still appear masked in plan
  diffs even though they are not `SecureString`. `insecure_value` is the only
  argument that shows in plaintext, and this module never uses it.
- **The unencrypted `SecureString` value is stored in plain text in Terraform
  state** — this is a provider-documented limitation, not a bug. State must be
  treated as sensitive (encrypted backend, restricted access) regardless of
  the parameter's `type`. Document this prominently for NPI-adjacent secrets.
- **`type` is NOT force-new by itself**, but downgrading `tier` from
  `Advanced` to `Standard` IS force-new (recreates the resource) — a caller
  narrowing tiers will see a destroy/create, not an in-place update.
- **`aws_ssm_document.operating_system` on patch baseline defaults to
  `WINDOWS` in the raw provider schema** — a caller who omits it on a Linux
  fleet silently gets a Windows baseline that matches nothing. This module
  requires the caller to set `operating_system` explicitly (no implicit
  default) to remove that foot-gun.
- **Patch baseline requires `approved_patches` OR `approval_rule`** — the
  provider allows both fields to be absent at the schema level but the API
  rejects the create; this module's variable validation enforces at least one
  is set.
- **`aws_ssm_document` schema-version-locked updates.** Only documents with
  `schemaVersion: "2.0"` or greater can update `content` in place; documents
  on `1.x` schemas force a new resource on any content change (not all
  `document_type` values support 2.0 — check AWS's document-schema-features
  reference per type before assuming in-place updates are possible).
- **`attachments_source` cannot be read back after creation** — the provider
  has no API to reconcile drift on this argument, so imported/pre-existing
  documents with attachments will show perpetual diffs unless the caller adds
  `lifecycle { ignore_changes = [attachments_source] }`. This module surfaces
  that guidance in the README rather than hard-coding `ignore_changes` (which
  would silently suppress legitimate attachment changes for callers who do
  manage attachments through Terraform).
- **`aws_ssm_maintenance_window` alone performs no work.** It only creates the
  schedule/cutoff/duration container; without at least one
  `aws_ssm_maintenance_window_target` and `aws_ssm_maintenance_window_task`,
  nothing executes. Both are in-scope child resources here (see In-scope
  resources) precisely so a single module call yields a working window.
- **`service_role_arn` omission triggers service-linked-role auto-creation.**
  If a maintenance window task's `service_role_arn` is left null, AWS uses
  (and creates, if absent) `AWSServiceRoleForAmazonSSM`. This is a real,
  audit-relevant account mutation the caller should be aware of even though
  Terraform does not directly manage that role.
- **`tags` vs `tags_all`.** `var.tags` (merged per-resource-type with a
  `Name` tag where applicable) flows to every taggable resource's `tags`
  argument; each resource's computed `tags_all` reflects the merge with
  provider `default_tags` (resource tags win on key conflict). `default_tags`
  remains the caller's provider-block concern, never set inside this module.
  Note `aws_ssm_maintenance_window_target` and `aws_ssm_maintenance_window_task`
  do **not** expose a `tags` argument in the current provider schema — they
  are not taggable resources, so `var.tags` does not reach them.
- **No `region` variable** — provider inheritance applies; SSM is a regional
  service with no us-east-1 global-resource coupling.
- **Destroy ordering:** patch groups must be deregistered before their patch
  baseline can be deleted if the baseline is still referenced; maintenance
  window targets/tasks must be deregistered before (or concurrently with, via
  normal dependency graph) the parent window — Terraform's implicit
  dependency graph (via `window_id` references) handles this automatically as
  long as targets/tasks are declared as child resources of this module (they
  are).

## Secure-by-default decisions

| Posture | Default | Opt-out |
|---|---|---|
| Parameter type | **`SecureString`** for every entry in `var.parameters` unless explicitly overridden | Set `type = "String"` (or `"StringList"`) per-parameter in the map; the variable's heredoc description documents this is for **non-secret values only** (e.g. feature flags, non-sensitive config) and is a per-parameter, explicit, visible opt-in — not a module-wide switch |
| SecureString encryption key | `key_id = null` → AWS-managed `alias/aws/ssm` key | Supply `kms_key_id` (from `terraform-aws-kms`) for a customer-managed CMK with caller-controlled key policy and rotation |
| Parameter overwrite protection | `overwrite = false` on first create (provider default), preventing accidental clobber of an out-of-band parameter with the same name | Provider automatically flips to `true` for all subsequent Terraform-managed updates; no module override needed |
| Document sharing (`permissions`) | Not set (private to the account) by default | Caller supplies a `permissions` block naming specific account IDs; the module does not support `"All"` (public) sharing — omitted from the schema entirely as a hard rail, since a public SSM document is a realistic NPI/config-leak vector |
| Patch baseline OS targeting | **Required, no default** — caller must state `operating_system` explicitly | N/A — this is a safety rail, not a relaxable default (see Provider gotchas) |
| Maintenance window task `service_role_arn` | Caller-suppliable; recommended explicit least-privilege role | Left null falls back to the SSM service-linked role — documented, not blocked, since the service-linked role is itself scoped by AWS |
| Association output logging | No S3/CloudWatch destination by default | Caller wires `output_s3_bucket_name` / `cloudwatch_log_group_name` from sibling modules for auditable command output |

## Design decisions

- **Parameters, documents, associations, patch baselines/groups, and
  maintenance windows are grouped into one composite** because they form a
  single operational domain (Systems Manager) with tight cross-references
  (an association names a document; a patch group names a baseline; a
  maintenance window task names a document or automation runbook) — splitting
  them into five separate modules would force callers to wire five sets of
  `for_each` keys back together for a single logical workflow (e.g. "patch
  this fleet weekly").
- **Every child collection is `map(object(...))` keyed by a caller-chosen
  stable string**, never `count`, consistent with the library-wide for_each
  standard — this lets callers add/remove a parameter or document without
  reindexing/recreating unrelated siblings.
- **`aws_ssm_parameter` is the keystone (`this`) even though most real
  deployments use several parameters**, because Parameter Store is
  overwhelmingly the most common entry point into this module and the
  single-resource-per-module convention names the keystone after the
  resource most callers reach for first; the resource itself is still
  `for_each`-driven internally to support N parameters per module call.
- **EC2 instances, instance profiles, KMS keys, and S3/CloudWatch log
  destinations are deliberately excluded** — they live in
  `terraform-aws-ec2-instance`, `terraform-aws-iam-role`, `terraform-aws-kms`, and
  `terraform-aws-s3-bucket` / `terraform-aws-cloudwatch-log-group` respectively,
  keeping this module's blast radius to the Systems Manager control plane
  itself and avoiding a composite that reaches across unrelated service
  boundaries.
- **Maintenance window targets and tasks are included** (a deliberate
  correction to the starting brief) because excluding them would ship a
  module that creates an inert maintenance window shell — the smallest useful
  unit for this composite is a window that actually runs something.
