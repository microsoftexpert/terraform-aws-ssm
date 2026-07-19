###############################################################################
# Parameter Store (keystone)
#
# for_each over var.parameters keyed by the parameter NAME itself — each.key
# is used directly as the "name" argument. SecureString is the default type
# (secure by default); key_id resolves per-entry override -> module-wide
# var.kms_key_id -> null (AWS-managed alias/aws/ssm key), and is only ever
# passed for SecureString entries.
###############################################################################

resource "aws_ssm_parameter" "this" {
 for_each = var.parameters

 name = each.key
 type = each.value.type
 value = each.value.value

 description = try(each.value.description, null)
 allowed_pattern = try(each.value.allowed_pattern, null)
 data_type = each.value.data_type
 tier = each.value.tier

 key_id = each.value.type != "SecureString" ? null: (try(each.value.key_id, null) != null ? each.value.key_id: var.kms_key_id)

 tags = merge(var.tags, try(each.value.tags, {}))
}

###############################################################################
# Documents — Command / Automation / Session / Policy / etc.
#
# "permissions" is a flat map(string) attribute in the provider schema (type,
# account_ids), not a nested block — rendered directly, never via dynamic.
# "attachments_source" IS a repeatable nested block.
###############################################################################

resource "aws_ssm_document" "this" {
 for_each = var.documents

 name = each.key
 content = each.value.content
 document_type = each.value.document_type
 document_format = each.value.document_format
 target_type = try(each.value.target_type, null)
 version_name = try(each.value.version_name, null)

 permissions = each.value.permissions == null ? null: {
 type = each.value.permissions.type
 account_ids = join(",", each.value.permissions.account_ids)
 }

 dynamic "attachments_source" {
 for_each = each.value.attachments_source
 content {
 key = attachments_source.value.key
 values = attachments_source.value.values
 name = try(attachments_source.value.name, null)
 }
 }

 tags = merge(var.tags, try(each.value.tags, {}))
}

###############################################################################
# State Manager associations
###############################################################################

resource "aws_ssm_association" "this" {
 for_each = var.associations

 name = each.value.document_name
 association_name = try(each.value.association_name, null)
 document_version = try(each.value.document_version, null)

 schedule_expression = try(each.value.schedule_expression, null)
 apply_only_at_cron_interval = each.value.apply_only_at_cron_interval
 compliance_severity = try(each.value.compliance_severity, null)
 max_concurrency = try(each.value.max_concurrency, null)
 max_errors = try(each.value.max_errors, null)
 automation_target_parameter_name = try(each.value.automation_target_parameter_name, null)
 calendar_names = each.value.calendar_names
 sync_compliance = try(each.value.sync_compliance, null)
 parameters = each.value.parameters
 wait_for_success_timeout_seconds = try(each.value.wait_for_success_timeout_seconds, null)

 dynamic "targets" {
 for_each = each.value.targets
 content {
 key = targets.value.key
 values = targets.value.values
 }
 }

 dynamic "output_location" {
 for_each = each.value.output_location != null ? [each.value.output_location]: []
 content {
 s3_bucket_name = output_location.value.s3_bucket_name
 s3_key_prefix = try(output_location.value.s3_key_prefix, null)
 s3_region = try(output_location.value.s3_region, null)
 }
 }

 tags = merge(var.tags, try(each.value.tags, {}))
}

###############################################################################
# Patch Manager — baselines
###############################################################################

resource "aws_ssm_patch_baseline" "this" {
 for_each = var.patch_baselines

 name = each.key
 description = try(each.value.description, null)
 operating_system = each.value.operating_system

 approved_patches = each.value.approved_patches
 approved_patches_compliance_level = each.value.approved_patches_compliance_level
 approved_patches_enable_non_security = each.value.approved_patches_enable_non_security
 available_security_updates_compliance_status = try(each.value.available_security_updates_compliance_status, null)
 rejected_patches = each.value.rejected_patches
 rejected_patches_action = try(each.value.rejected_patches_action, null)

 dynamic "global_filter" {
 for_each = each.value.global_filter
 content {
 key = global_filter.value.key
 values = global_filter.value.values
 }
 }

 dynamic "approval_rule" {
 for_each = each.value.approval_rule
 content {
 approve_after_days = try(approval_rule.value.approve_after_days, null)
 approve_until_date = try(approval_rule.value.approve_until_date, null)
 compliance_level = approval_rule.value.compliance_level
 enable_non_security = approval_rule.value.enable_non_security

 dynamic "patch_filter" {
 for_each = approval_rule.value.patch_filter
 content {
 key = patch_filter.value.key
 values = patch_filter.value.values
 }
 }
 }
 }

 dynamic "source" {
 for_each = each.value.source
 content {
 name = source.value.name
 products = source.value.products
 configuration = source.value.configuration
 }
 }

 tags = merge(var.tags, try(each.value.tags, {}))
}

###############################################################################
# Patch Manager — patch group registrations
#
# No tags argument in the provider schema — not taggable.
###############################################################################

resource "aws_ssm_patch_group" "this" {
 for_each = var.patch_groups

 baseline_id = aws_ssm_patch_baseline.this[each.value.baseline_key].id
 patch_group = each.value.patch_group
}

###############################################################################
# Maintenance windows
###############################################################################

resource "aws_ssm_maintenance_window" "this" {
 for_each = var.maintenance_windows

 name = each.key
 schedule = each.value.schedule
 cutoff = each.value.cutoff
 duration = each.value.duration

 description = try(each.value.description, null)
 allow_unassociated_targets = each.value.allow_unassociated_targets
 enabled = each.value.enabled
 end_date = try(each.value.end_date, null)
 start_date = try(each.value.start_date, null)
 schedule_timezone = try(each.value.schedule_timezone, null)
 schedule_offset = try(each.value.schedule_offset, null)

 tags = merge(var.tags, try(each.value.tags, {}))
}

###############################################################################
# Maintenance window targets
#
# No tags argument, no arn attribute in the provider schema — not taggable.
###############################################################################

resource "aws_ssm_maintenance_window_target" "this" {
 for_each = var.maintenance_window_targets

 window_id = aws_ssm_maintenance_window.this[each.value.window_key].id
 resource_type = each.value.resource_type
 name = try(each.value.name, null)
 description = try(each.value.description, null)
 owner_information = try(each.value.owner_information, null)

 dynamic "targets" {
 for_each = each.value.targets
 content {
 key = targets.value.key
 values = targets.value.values
 }
 }
}

###############################################################################
# Maintenance window tasks
#
# No tags argument in the provider schema — not taggable (despite exposing an
# arn attribute). service_role_arn left null falls back to (and triggers
# auto-creation of, if absent) AWSServiceRoleForAmazonSSM.
###############################################################################

resource "aws_ssm_maintenance_window_task" "this" {
 for_each = var.maintenance_window_tasks

 window_id = aws_ssm_maintenance_window.this[each.value.window_key].id
 task_type = each.value.task_type
 task_arn = each.value.task_arn
 priority = each.value.priority
 max_concurrency = try(each.value.max_concurrency, null)
 max_errors = try(each.value.max_errors, null)
 cutoff_behavior = try(each.value.cutoff_behavior, null)
 service_role_arn = try(each.value.service_role_arn, null)
 name = try(each.value.name, null)
 description = try(each.value.description, null)

 dynamic "targets" {
 for_each = try(each.value.targets, [])
 content {
 key = targets.value.key
 values = targets.value.values
 }
 }

 dynamic "task_invocation_parameters" {
 for_each = each.value.task_invocation_parameters != null ? [each.value.task_invocation_parameters]: []
 content {
 dynamic "automation_parameters" {
 for_each = task_invocation_parameters.value.automation_parameters != null ? [task_invocation_parameters.value.automation_parameters]: []
 content {
 document_version = try(automation_parameters.value.document_version, null)

 dynamic "parameter" {
 for_each = try(automation_parameters.value.parameter, [])
 content {
 name = parameter.value.name
 values = parameter.value.values
 }
 }
 }
 }

 dynamic "lambda_parameters" {
 for_each = task_invocation_parameters.value.lambda_parameters != null ? [task_invocation_parameters.value.lambda_parameters]: []
 content {
 client_context = try(lambda_parameters.value.client_context, null)
 payload = try(lambda_parameters.value.payload, null)
 qualifier = try(lambda_parameters.value.qualifier, null)
 }
 }

 dynamic "run_command_parameters" {
 for_each = task_invocation_parameters.value.run_command_parameters != null ? [task_invocation_parameters.value.run_command_parameters]: []
 content {
 comment = try(run_command_parameters.value.comment, null)
 document_hash = try(run_command_parameters.value.document_hash, null)
 document_hash_type = try(run_command_parameters.value.document_hash_type, null)
 output_s3_bucket = try(run_command_parameters.value.output_s3_bucket, null)
 output_s3_key_prefix = try(run_command_parameters.value.output_s3_key_prefix, null)
 service_role_arn = try(run_command_parameters.value.service_role_arn, null)
 timeout_seconds = try(run_command_parameters.value.timeout_seconds, null)

 dynamic "parameter" {
 for_each = try(run_command_parameters.value.parameter, [])
 content {
 name = parameter.value.name
 values = parameter.value.values
 }
 }

 dynamic "notification_config" {
 for_each = run_command_parameters.value.notification_config != null ? [run_command_parameters.value.notification_config]: []
 content {
 notification_arn = try(notification_config.value.notification_arn, null)
 notification_events = try(notification_config.value.notification_events, null)
 notification_type = try(notification_config.value.notification_type, null)
 }
 }

 dynamic "cloudwatch_config" {
 for_each = run_command_parameters.value.cloudwatch_config != null ? [run_command_parameters.value.cloudwatch_config]: []
 content {
 cloudwatch_log_group_name = try(cloudwatch_config.value.cloudwatch_log_group_name, null)
 cloudwatch_output_enabled = try(cloudwatch_config.value.cloudwatch_output_enabled, null)
 }
 }
 }
 }

 dynamic "step_functions_parameters" {
 for_each = task_invocation_parameters.value.step_functions_parameters != null ? [task_invocation_parameters.value.step_functions_parameters]: []
 content {
 input = try(step_functions_parameters.value.input, null)
 name = try(step_functions_parameters.value.name, null)
 }
 }
 }
 }
}
