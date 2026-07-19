###############################################################################
# Parameter Store — keystone (aws_ssm_parameter.this)
#
# for_each over a caller-supplied map keyed by the parameter NAME itself (each
# map key is used directly as the aws_ssm_parameter "name" argument, so keys
# must be valid SSM parameter names, e.g. "/app/db/password"). Secure by
# default: every entry is SecureString unless the caller explicitly opts a
# specific entry into String/StringList for non-secret values.
###############################################################################

variable "parameters" {
 description = <<EOT
Map of SSM Parameter Store entries keyed by the parameter's NAME (the key is
used directly as the aws_ssm_parameter "name" argument — e.g.
"/app/prod/db/password"). REQUIRED — this module's keystone.

 parameters = {
 "/app/prod/db/password" = { value = var.db_password }
 "/app/prod/feature/flag_x" = { value = "true", type = "String" }
 }

Per-entry fields:
 - value: (Required) Parameter value. Always shown masked in
 plan output regardless of type (provider behavior).
 The unencrypted SecureString value is nonetheless
 stored in plain text in Terraform state — treat
 state as sensitive.
 - type: (Optional) "SecureString" (default — secure
 baseline), "String", or "StringList". Set to
 "String"/"StringList" per-entry ONLY for non-secret
 values (feature flags, non-sensitive config) — this
 is a deliberate, visible, per-parameter opt-out,
 never a module-wide switch.
 - description: (Optional) Parameter description.
 - allowed_pattern: (Optional) Regex used to validate the value.
 - data_type: (Optional) "text" (default), "aws:ssm:integration",
 or "aws:ec2:image".
 - tier: (Optional) "Standard" (default), "Advanced", or
 "Intelligent-Tiering". Downgrading Advanced ->
 Standard is FORCE-NEW (recreates the parameter).
 - key_id: (Optional) Per-parameter KMS key ID/ARN for
 SecureString encryption; overrides var.kms_key_id
 for this entry only. Ignored for String/StringList.
 - tags: (Optional) Extra tags merged over module tags.
EOT
 type = map(object({
 value = string
 type = optional(string, "SecureString")
 description = optional(string)
 allowed_pattern = optional(string)
 data_type = optional(string, "text")
 tier = optional(string, "Standard")
 key_id = optional(string)
 tags = optional(map(string), {})
 }))

 validation {
 condition = alltrue([for k, v in var.parameters: contains(["String", "StringList", "SecureString"], v.type)])
 error_message = "Every parameters entry's type must be one of: String, StringList, SecureString."
 }

 validation {
 condition = alltrue([for k, v in var.parameters: contains(["text", "aws:ssm:integration", "aws:ec2:image"], v.data_type)])
 error_message = "Every parameters entry's data_type must be one of: text, aws:ssm:integration, aws:ec2:image."
 }

 validation {
 condition = alltrue([for k, v in var.parameters: contains(["Standard", "Advanced", "Intelligent-Tiering"], v.tier)])
 error_message = "Every parameters entry's tier must be one of: Standard, Advanced, Intelligent-Tiering."
 }

 validation {
 condition = alltrue([for k, v in var.parameters: length(v.value) > 0])
 error_message = "Every parameters entry's value must be a non-empty string."
 }
}

###############################################################################
# SecureString encryption — module-wide default CMK
###############################################################################

variable "kms_key_id" {
 description = <<EOT
Default KMS key ID or ARN used to encrypt every SecureString entry in
var.parameters that does not set its own per-entry key_id. Null (default)
uses the AWS-managed alias/aws/ssm key. Wire from tf-mod-aws-kms (arn output)
for a customer-managed CMK with caller-controlled key policy and rotation.
Ignored for String/StringList entries.
EOT
 type = string
 default = null
}

###############################################################################
# Documents (Command / Automation / Session / Policy / etc.) — child collection
###############################################################################

variable "documents" {
 description = <<EOT
Map of SSM Documents keyed by a stable name (the key is used directly as the
aws_ssm_document "name" argument). Optional child collection — defaults to {}.

 documents = {
 my-runbook = {
 document_type = "Command"
 content = file("$${path.module}/documents/my-runbook.json")
 }
 }

Per-entry fields:
 - content: (Required) JSON or YAML document content (<= 64KB).
 Only schemaVersion >= "2.0" documents can update
 content in place; older schema versions FORCE-NEW on
 any content change.
 - document_type: (Required) One of: Command, Policy, Automation,
 Session, Package, ApplicationConfiguration,
 ApplicationConfigurationSchema, DeploymentStrategy,
 ChangeCalendar, Automation.ChangeTemplate,
 ProblemAnalysis, ProblemAnalysisTemplate,
 CloudFormation, ConformancePackTemplate, QuickSetup.
 - document_format: (Optional) "JSON" (default), "TEXT", or "YAML".
 - target_type: (Optional) Resource type the document targets, e.g.
 "/AWS::EC2::Instance".
 - version_name: (Optional) Unique version label for this document.
 - permissions: (Optional) Sharing config. account_ids names specific
 AWS account IDs only — this module does NOT support
 "All" (public) sharing; a public SSM document is a
 realistic PII/config-leak vector and is hard-blocked.
 - type: (Optional) "Share" (default; the only provider value).
 - account_ids: (Required if permissions set) List of AWS account IDs
 to share the document with. Never "All".
 - attachments_source: (Optional) List of attachment sources. Cannot be read
 back after creation (no reconciling API) — imported
 documents with attachments will show a perpetual diff
 unless the caller adds a lifecycle ignore_changes.
 - key: (Required) One of: SourceUrl, S3FileUrl,
 AttachmentReference.
 - values: (Required) Location value(s) for the key.
 - name: (Optional) Attachment file name.
 - tags: (Optional) Extra tags merged over module tags.
EOT
 type = map(object({
 content = string
 document_type = string

 document_format = optional(string, "JSON")
 target_type = optional(string)
 version_name = optional(string)

 permissions = optional(object({
 type = optional(string, "Share")
 account_ids = list(string)
 }))

 attachments_source = optional(list(object({
 key = string
 values = list(string)
 name = optional(string)
 })), [])

 tags = optional(map(string), {})
 }))
 default = {}

 validation {
 condition = alltrue([
 for k, v in var.documents: contains([
 "Command", "Policy", "Automation", "Session", "Package",
 "ApplicationConfiguration", "ApplicationConfigurationSchema",
 "DeploymentStrategy", "ChangeCalendar", "Automation.ChangeTemplate",
 "ProblemAnalysis", "ProblemAnalysisTemplate", "CloudFormation",
 "ConformancePackTemplate", "QuickSetup"
 ], v.document_type)
 ])
 error_message = "Every documents entry's document_type must be a valid SSM document type (see variable description)."
 }

 validation {
 condition = alltrue([for k, v in var.documents: contains(["JSON", "TEXT", "YAML"], v.document_format)])
 error_message = "Every documents entry's document_format must be one of: JSON, TEXT, YAML."
 }

 validation {
 condition = alltrue([
 for k, v in var.documents:
 v.permissions == null ? true: alltrue([for a in v.permissions.account_ids: lower(a) != "all"])
 ])
 error_message = "documents[*].permissions.account_ids must name specific AWS account IDs — public (\"All\") document sharing is not supported by this module."
 }

 validation {
 condition = alltrue([
 for k, v in var.documents:
 alltrue([for s in v.attachments_source: contains(["SourceUrl", "S3FileUrl", "AttachmentReference"], s.key)])
 ])
 error_message = "Every documents[*].attachments_source entry's key must be one of: SourceUrl, S3FileUrl, AttachmentReference."
 }
}

###############################################################################
# State Manager associations — child collection
###############################################################################

variable "associations" {
 description = <<EOT
Map of State Manager associations keyed by a stable name. Binds a document
(this module's own via document_name, or an AWS-owned/public document name
such as "AWS-RunPatchBaseline") to a set of targets on a schedule. Optional
child collection — defaults to {}.

 associations = {
 patch-fleet = {
 document_name = "AWS-RunPatchBaseline"
 schedule_expression = "cron(0 2 ? * SUN *)"
 targets = [{ key = "tag:PatchGroup", values = ["prod-linux"] }]
 }
 }

Per-entry fields:
 - document_name: (Required) Name of the SSM document to
 apply — either an aws_ssm_document key's
 resulting name (see document_names
 output) or an AWS-owned document name.
 - targets: (Required) Up to 5 target blocks.
 - key: (Required) e.g. "InstanceIds", "tag:Key".
 - values: (Required) Matching values.
 - association_name: (Optional) Descriptive association name.
 - document_version: (Optional) Specific version or "$DEFAULT".
 - schedule_expression: (Optional) Cron or rate expression.
 - apply_only_at_cron_interval: (Optional) Default false (run immediately
 on create/update, then on schedule).
 - compliance_severity: (Optional) UNSPECIFIED, LOW, MEDIUM,
 HIGH, or CRITICAL.
 - max_concurrency: (Optional) Number or percentage string.
 - max_errors: (Optional) Number or percentage string.
 - automation_target_parameter_name: (Optional) Required only for Automation
 rate-control documents.
 - calendar_names: (Optional) Change Calendar names gating
 when the association runs.
 - sync_compliance: (Optional) "AUTO" or "MANUAL".
 - parameters: (Optional) Map of string parameters
 passed to the SSM document.
 - output_location: (Optional) S3 destination for command
 output.
 - s3_bucket_name: (Required) Bucket name — wire from
 tf-mod-aws-s3-bucket.
 - s3_key_prefix: (Optional) Bucket prefix.
 - s3_region: (Optional) Bucket region.
 - wait_for_success_timeout_seconds: (Optional) Seconds to wait for Success.
 - tags: (Optional) Extra tags merged over module
 tags.
EOT
 type = map(object({
 document_name = string
 targets = list(object({
 key = string
 values = list(string)
 }))

 association_name = optional(string)
 document_version = optional(string)
 schedule_expression = optional(string)
 apply_only_at_cron_interval = optional(bool, false)
 compliance_severity = optional(string)
 max_concurrency = optional(string)
 max_errors = optional(string)
 automation_target_parameter_name = optional(string)
 calendar_names = optional(list(string), [])
 sync_compliance = optional(string)
 parameters = optional(map(string), {})
 wait_for_success_timeout_seconds = optional(number)

 output_location = optional(object({
 s3_bucket_name = string
 s3_key_prefix = optional(string)
 s3_region = optional(string)
 }))

 tags = optional(map(string), {})
 }))
 default = {}

 validation {
 condition = alltrue([for k, v in var.associations: length(v.targets) <= 5])
 error_message = "Every associations entry supports a maximum of 5 targets (AWS service limit)."
 }

 validation {
 condition = alltrue([
 for k, v in var.associations:
 v.compliance_severity == null ? true: contains(["UNSPECIFIED", "LOW", "MEDIUM", "HIGH", "CRITICAL"], v.compliance_severity)
 ])
 error_message = "Every associations entry's compliance_severity must be one of: UNSPECIFIED, LOW, MEDIUM, HIGH, CRITICAL."
 }

 validation {
 condition = alltrue([
 for k, v in var.associations:
 v.sync_compliance == null ? true: contains(["AUTO", "MANUAL"], v.sync_compliance)
 ])
 error_message = "Every associations entry's sync_compliance must be one of: AUTO, MANUAL."
 }
}

###############################################################################
# Patch Manager — baselines — child collection
#
# operating_system is REQUIRED with no implicit default on this module's
# variable (unlike the raw provider schema, which silently defaults to
# WINDOWS) — a caller who omits it on a Linux fleet must not silently get a
# baseline that matches nothing.
###############################################################################

variable "patch_baselines" {
 description = <<EOT
Map of Patch Manager baselines keyed by a stable name. Optional child
collection — defaults to {}. operating_system has NO default (safety rail —
the raw provider schema defaults it to WINDOWS, a foot-gun for Linux fleets).
Exactly one of approved_patches or approval_rule must be set per entry (the
provider rejects both being empty AND rejects both being set simultaneously).

 patch_baselines = {
 linux-prod = {
 operating_system = "AMAZON_LINUX_2023"
 approval_rule = [{
 approve_after_days = 7
 patch_filter = [{ key = "CLASSIFICATION", values = ["Security"] }]
 }]
 }
 }

Per-entry fields:
 - operating_system: (Required, no default) One
 of: ALMA_LINUX,
 AMAZON_LINUX,
 AMAZON_LINUX_2,
 AMAZON_LINUX_2022,
 AMAZON_LINUX_2023, CENTOS,
 DEBIAN, MACOS,
 ORACLE_LINUX, RASPBIAN,
 REDHAT_ENTERPRISE_LINUX,
 ROCKY_LINUX, SUSE, UBUNTU,
 WINDOWS.
 - description: (Optional) Baseline
 description.
 - approved_patches: (Optional) Explicit
 approved-patch IDs.
 Cannot be combined with
 approval_rule.
 - approved_patches_compliance_level: (Optional) CRITICAL, HIGH,
 MEDIUM, LOW,
 INFORMATIONAL, or
 UNSPECIFIED (default).
 - approved_patches_enable_non_security: (Optional) Linux only.
 Default false.
 - available_security_updates_compliance_status: (Optional) Windows only.
 COMPLIANT or NON_COMPLIANT.
 - rejected_patches: (Optional) Rejected patch
 IDs.
 - rejected_patches_action: (Optional)
 ALLOW_AS_DEPENDENCY or
 BLOCK.
 - global_filter: (Optional) Up to 4 filters
 excluding patches.
 - key: PRODUCT, CLASSIFICATION,
 MSRC_SEVERITY, or
 PATCH_ID.
 - values: Matching values.
 - approval_rule: (Optional) Up to 10 rules.
 Cannot be combined with
 approved_patches.
 - approve_after_days: Days after release until
 auto-approved (0-360).
 Conflicts with
 approve_until_date.
 - approve_until_date: "YYYY-MM-DD" cutoff.
 Conflicts with
 approve_after_days.
 - compliance_level: Default UNSPECIFIED.
 - enable_non_security: Linux only. Default false.
 - patch_filter: (Required) Up to 5
 key/values filters per
 rule.
 - source: (Optional) Linux-only
 alternate patch
 repositories.
 - name / products / configuration: (Required) See AWS docs.
 - tags: (Optional) Extra tags
 merged over module tags.
EOT
 type = map(object({
 operating_system = string

 description = optional(string)
 approved_patches = optional(list(string), [])
 approved_patches_compliance_level = optional(string, "UNSPECIFIED")
 approved_patches_enable_non_security = optional(bool, false)
 available_security_updates_compliance_status = optional(string)
 rejected_patches = optional(list(string), [])
 rejected_patches_action = optional(string)

 global_filter = optional(list(object({
 key = string
 values = list(string)
 })), [])

 approval_rule = optional(list(object({
 approve_after_days = optional(number)
 approve_until_date = optional(string)
 compliance_level = optional(string, "UNSPECIFIED")
 enable_non_security = optional(bool, false)
 patch_filter = list(object({
 key = string
 values = list(string)
 }))
 })), [])

 source = optional(list(object({
 name = string
 products = list(string)
 configuration = string
 })), [])

 tags = optional(map(string), {})
 }))
 default = {}

 validation {
 condition = alltrue([
 for k, v in var.patch_baselines: contains([
 "ALMA_LINUX", "AMAZON_LINUX", "AMAZON_LINUX_2", "AMAZON_LINUX_2022",
 "AMAZON_LINUX_2023", "CENTOS", "DEBIAN", "MACOS", "ORACLE_LINUX",
 "RASPBIAN", "REDHAT_ENTERPRISE_LINUX", "ROCKY_LINUX", "SUSE",
 "UBUNTU", "WINDOWS"
 ], v.operating_system)
 ])
 error_message = "Every patch_baselines entry's operating_system must be a valid SSM Patch Manager OS value (see variable description)."
 }

 validation {
 condition = alltrue([
 for k, v in var.patch_baselines:
 (length(v.approved_patches) > 0 || length(v.approval_rule) > 0) &&
 !(length(v.approved_patches) > 0 && length(v.approval_rule) > 0)
 ])
 error_message = "Every patch_baselines entry must set exactly one of approved_patches or approval_rule (not both, not neither) — the provider rejects both an empty baseline and a baseline that combines both."
 }

 validation {
 condition = alltrue([for k, v in var.patch_baselines: length(v.global_filter) <= 4])
 error_message = "Every patch_baselines entry supports a maximum of 4 global_filter blocks (AWS service limit)."
 }

 validation {
 condition = alltrue([for k, v in var.patch_baselines: length(v.approval_rule) <= 10])
 error_message = "Every patch_baselines entry supports a maximum of 10 approval_rule blocks (AWS service limit)."
 }

 validation {
 condition = alltrue([
 for k, v in var.patch_baselines:
 alltrue([for r in v.approval_rule: length(r.patch_filter) <= 5])
 ])
 error_message = "Every patch_baselines[*].approval_rule entry supports a maximum of 5 patch_filter blocks (AWS service limit)."
 }
}

###############################################################################
# Patch Manager — patch group registrations — child collection
#
# aws_ssm_patch_group has no tags argument and no arn attribute in the current
# provider schema (not taggable), so var.tags does not reach it.
###############################################################################

variable "patch_groups" {
 description = <<EOT
Map of Patch Group registrations keyed by a stable name. Registers a patch
group name against one of this module's own patch_baselines entries. Optional
child collection — defaults to {}. Not taggable (no tags/arn in the provider
schema).

 patch_groups = {
 prod-linux = { baseline_key = "linux-prod", patch_group = "prod-linux" }
 }

Per-entry fields:
 - baseline_key: (Required) Key into var.patch_baselines identifying which
 baseline this patch group registers against.
 - patch_group: (Required) The patch group name applied to target
 instances (typically via a "Patch Group" tag).
EOT
 type = map(object({
 baseline_key = string
 patch_group = string
 }))
 default = {}

 validation {
 condition = alltrue([for k, v in var.patch_groups: contains(keys(var.patch_baselines), v.baseline_key)])
 error_message = "Every patch_groups entry's baseline_key must reference a key present in var.patch_baselines."
 }
}

###############################################################################
# Maintenance windows — child collection
###############################################################################

variable "maintenance_windows" {
 description = <<EOT
Map of Maintenance Windows keyed by a stable name (the key is used directly as
the aws_ssm_maintenance_window "name" argument). Optional child collection —
defaults to {}. A window alone performs no work; pair it with
maintenance_window_targets and maintenance_window_tasks entries that reference
this window's key.

 maintenance_windows = {
 weekly-patch = { schedule = "cron(0 16 ? * TUE *)", duration = 3, cutoff = 1 }
 }

Per-entry fields:
 - schedule: (Required) Cron or rate expression.
 - cutoff: (Required) Hours before window end that new
 task scheduling stops. Must be < duration.
 - duration: (Required) Window duration in hours.
 - description: (Optional) Window description.
 - allow_unassociated_targets: (Optional) Default false.
 - enabled: (Optional) Default true.
 - end_date / start_date: (Optional) ISO-8601 bounds.
 - schedule_timezone: (Optional) IANA timezone, e.g. "America/Chicago".
 - schedule_offset: (Optional) 1-6 days to wait after the cron
 match before running.
 - tags: (Optional) Extra tags merged over module tags.
EOT
 type = map(object({
 schedule = string
 cutoff = number
 duration = number

 description = optional(string)
 allow_unassociated_targets = optional(bool, false)
 enabled = optional(bool, true)
 end_date = optional(string)
 start_date = optional(string)
 schedule_timezone = optional(string)
 schedule_offset = optional(number)

 tags = optional(map(string), {})
 }))
 default = {}

 validation {
 condition = alltrue([for k, v in var.maintenance_windows: v.cutoff < v.duration])
 error_message = "Every maintenance_windows entry's cutoff must be less than its duration."
 }

 validation {
 condition = alltrue([
 for k, v in var.maintenance_windows:
 v.schedule_offset == null ? true: (v.schedule_offset >= 1 && v.schedule_offset <= 6)
 ])
 error_message = "Every maintenance_windows entry's schedule_offset, if set, must be between 1 and 6."
 }
}

###############################################################################
# Maintenance window targets — child collection
#
# aws_ssm_maintenance_window_target has no tags argument and no arn attribute
# in the current provider schema (not taggable), so var.tags does not reach
# it.
###############################################################################

variable "maintenance_window_targets" {
 description = <<EOT
Map of Maintenance Window target registrations keyed by a stable name.
Optional child collection — defaults to {}. Not taggable (no tags/arn in the
provider schema).

 maintenance_window_targets = {
 prod-fleet = {
 window_key = "weekly-patch"
 resource_type = "INSTANCE"
 targets = [{ key = "tag:PatchGroup", values = ["prod-linux"] }]
 }
 }

Per-entry fields:
 - window_key: (Required) Key into var.maintenance_windows this
 target registers against.
 - resource_type: (Required) "INSTANCE" or "RESOURCE_GROUP".
 - targets: (Required) Instance IDs, resource group filters, or
 tags identifying the target instances.
 - key: (Required) e.g. "InstanceIds", "tag:Name",
 "resource-groups:ResourceTypeFilters".
 - values: (Required) Matching values.
 - name: (Optional) Target display name.
 - description: (Optional) Target description.
 - owner_information: (Optional) Free-form value surfaced on CloudWatch
 events raised while running tasks for this target.
EOT
 type = map(object({
 window_key = string
 resource_type = string
 targets = list(object({
 key = string
 values = list(string)
 }))

 name = optional(string)
 description = optional(string)
 owner_information = optional(string)
 }))
 default = {}

 validation {
 condition = alltrue([for k, v in var.maintenance_window_targets: contains(["INSTANCE", "RESOURCE_GROUP"], v.resource_type)])
 error_message = "Every maintenance_window_targets entry's resource_type must be one of: INSTANCE, RESOURCE_GROUP."
 }

 validation {
 condition = alltrue([for k, v in var.maintenance_window_targets: contains(keys(var.maintenance_windows), v.window_key)])
 error_message = "Every maintenance_window_targets entry's window_key must reference a key present in var.maintenance_windows."
 }
}

###############################################################################
# Maintenance window tasks — child collection
#
# aws_ssm_maintenance_window_task has no tags argument (not taggable) despite
# exposing an arn attribute.
###############################################################################

variable "maintenance_window_tasks" {
 description = <<EOT
Map of Maintenance Window task registrations keyed by a stable name. Optional
child collection — defaults to {}. A window with no registered task performs
no work; Patch Manager's own quick-setup pattern registers a RUN_COMMAND task
(AWS-RunPatchBaseline) against a window target, which this module supports
directly. Not taggable (no tags argument in the provider schema).

 maintenance_window_tasks = {
 run-patch-baseline = {
 window_key = "weekly-patch"
 task_type = "RUN_COMMAND"
 task_arn = "AWS-RunPatchBaseline"
 targets = [{ key = "WindowTargetIds", values = ["<target-id>"] }]
 }
 }

Per-entry fields:
 - window_key: (Required) Key into var.maintenance_windows
 this task registers against.
 - task_type: (Required) AUTOMATION, LAMBDA, RUN_COMMAND,
 or STEP_FUNCTIONS.
 - task_arn: (Required) ARN or AWS-owned document name of
 the task to execute (e.g. "AWS-RunShellScript",
 "AWS-RunPatchBaseline", a Lambda function
 ARN, or an SFN activity ARN).
 - priority: (Optional) Lower runs first. Default 1.
 - max_concurrency: (Optional) Number or percentage string.
 - max_errors: (Optional) Number or percentage string.
 - cutoff_behavior: (Optional) CONTINUE_TASK or CANCEL_TASK.
 - service_role_arn: (Optional) IAM role assumed to run the task.
 Null falls back to (and triggers auto-create
 of, if absent) the AWSServiceRoleForAmazonSSM
 service-linked role — an audit-relevant,
 account-level side effect worth flagging in
 change review. Wire from tf-mod-aws-iam-role
 for an explicit, least-privilege role.
 - name / description: (Optional) Task display name/description.
 - targets: (Optional) InstanceIds or WindowTargetIds
 referencing a maintenance_window_targets
 entry's id.
 - task_invocation_parameters: (Optional) Exactly one of the nested blocks
 below matching task_type.
 - automation_parameters: document_version, parameter[] (name/values)
 - lambda_parameters: client_context, payload, qualifier
 - run_command_parameters: comment, document_hash,
 document_hash_type (Sha256|Sha1),
 output_s3_bucket, output_s3_key_prefix,
 service_role_arn, timeout_seconds,
 parameter[] (name/values),
 notification_config
 (notification_arn, notification_events,
 notification_type: Command|Invocation),
 cloudwatch_config
 (cloudwatch_log_group_name,
 cloudwatch_output_enabled)
 - step_functions_parameters: input, name
EOT
 type = map(object({
 window_key = string
 task_type = string
 task_arn = string

 priority = optional(number, 1)
 max_concurrency = optional(string)
 max_errors = optional(string)
 cutoff_behavior = optional(string)
 service_role_arn = optional(string)
 name = optional(string)
 description = optional(string)

 targets = optional(list(object({
 key = string
 values = list(string)
 })), [])

 task_invocation_parameters = optional(object({
 automation_parameters = optional(object({
 document_version = optional(string)
 parameter = optional(list(object({
 name = string
 values = list(string)
 })), [])
 }))

 lambda_parameters = optional(object({
 client_context = optional(string)
 payload = optional(string)
 qualifier = optional(string)
 }))

 run_command_parameters = optional(object({
 comment = optional(string)
 document_hash = optional(string)
 document_hash_type = optional(string)
 output_s3_bucket = optional(string)
 output_s3_key_prefix = optional(string)
 service_role_arn = optional(string)
 timeout_seconds = optional(number)

 parameter = optional(list(object({
 name = string
 values = list(string)
 })), [])

 notification_config = optional(object({
 notification_arn = optional(string)
 notification_events = optional(list(string), [])
 notification_type = optional(string)
 }))

 cloudwatch_config = optional(object({
 cloudwatch_log_group_name = optional(string)
 cloudwatch_output_enabled = optional(bool, false)
 }))
 }))

 step_functions_parameters = optional(object({
 input = optional(string)
 name = optional(string)
 }))
 }))
 }))
 default = {}

 validation {
 condition = alltrue([for k, v in var.maintenance_window_tasks: contains(["AUTOMATION", "LAMBDA", "RUN_COMMAND", "STEP_FUNCTIONS"], v.task_type)])
 error_message = "Every maintenance_window_tasks entry's task_type must be one of: AUTOMATION, LAMBDA, RUN_COMMAND, STEP_FUNCTIONS."
 }

 validation {
 condition = alltrue([
 for k, v in var.maintenance_window_tasks:
 v.cutoff_behavior == null ? true: contains(["CONTINUE_TASK", "CANCEL_TASK"], v.cutoff_behavior)
 ])
 error_message = "Every maintenance_window_tasks entry's cutoff_behavior, if set, must be one of: CONTINUE_TASK, CANCEL_TASK."
 }

 validation {
 condition = alltrue([for k, v in var.maintenance_window_tasks: contains(keys(var.maintenance_windows), v.window_key)])
 error_message = "Every maintenance_window_tasks entry's window_key must reference a key present in var.maintenance_windows."
 }

 validation {
 condition = alltrue([
 for k, v in var.maintenance_window_tasks:
 v.task_invocation_parameters == null || v.task_invocation_parameters.run_command_parameters == null ||
 v.task_invocation_parameters.run_command_parameters.document_hash_type == null ||
 contains(["Sha256", "Sha1"], v.task_invocation_parameters.run_command_parameters.document_hash_type)
 ])
 error_message = "run_command_parameters.document_hash_type, if set, must be one of: Sha256, Sha1."
 }

 validation {
 condition = alltrue([
 for k, v in var.maintenance_window_tasks:
 v.task_invocation_parameters == null || v.task_invocation_parameters.run_command_parameters == null ||
 v.task_invocation_parameters.run_command_parameters.notification_config == null ||
 v.task_invocation_parameters.run_command_parameters.notification_config.notification_type == null ||
 contains(["Command", "Invocation"], v.task_invocation_parameters.run_command_parameters.notification_config.notification_type)
 ])
 error_message = "run_command_parameters.notification_config.notification_type, if set, must be one of: Command, Invocation."
 }
}

###############################################################################
# Universal tail
###############################################################################

variable "tags" {
 description = <<EOT
A map of tags to assign to every taggable resource created by this module
(parameters, documents, associations, patch baselines, maintenance windows).
These merge with provider-level default_tags; resource tags win on key
conflict. Per-entry tags merge over these: merge(var.tags, each.value.tags).
The computed tags_all outputs reflect the merged set per resource type. Note
aws_ssm_patch_group, aws_ssm_maintenance_window_target, and
aws_ssm_maintenance_window_task do NOT accept a tags argument in the current
provider schema — they are not taggable, so var.tags does not reach them.
EOT
 type = map(string)
 default = {}
}
