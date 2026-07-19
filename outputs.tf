###############################################################################
# Primary outputs — Parameter Store (keystone)
#
# Keyed by the caller's parameter name (each.key) since the keystone is
# for_each-driven, not a single resource.
###############################################################################

output "id" {
 description = "Map of parameter name => aws_ssm_parameter id (identical to the parameter name) for every entry in var.parameters."
 value = { for k, p in aws_ssm_parameter.this: k => p.id }
}

output "arn" {
 description = <<EOT
Map of parameter name => parameter ARN
(arn:aws:ssm:<region>:<account>:parameter/<name>, without the leading slash
duplicated). Cross-resource reference type — consumed by tf-mod-aws-iam-policy
(scoping ssm:GetParameter resource ARNs) and tf-mod-aws-ecs-service
(secrets valueFrom).
EOT
 value = { for k, p in aws_ssm_parameter.this: k => p.arn }
}

output "name" {
 description = "Map of parameter name => parameter name (identical to the key, echoed for symmetry with other modules' name output)."
 value = { for k, p in aws_ssm_parameter.this: k => p.name }
}

output "version" {
 description = "Map of parameter name => current parameter version. Increments on every value update."
 value = { for k, p in aws_ssm_parameter.this: k => p.version }
}

output "tags_all" {
 description = "Map of parameter name => merged tags on the parameter, including those inherited from provider default_tags (resource tags win on key conflict)."
 value = { for k, p in aws_ssm_parameter.this: k => p.tags_all }
}

###############################################################################
# Documents
###############################################################################

output "document_ids" {
 description = "Map of document key => document id (the document name)."
 value = { for k, d in aws_ssm_document.this: k => d.id }
}

output "document_arns" {
 description = "Map of document key => document ARN. Consumed by aws_ssm_association.name references and tf-mod-aws-ec2-instance user-data bootstrapping references."
 value = { for k, d in aws_ssm_document.this: k => d.arn }
}

output "document_names" {
 description = "Map of document key => document name. Consumed by aws_ssm_association and CLI/console cross-reference."
 value = { for k, d in aws_ssm_document.this: k => d.name }
}

output "document_tags_all" {
 description = "Map of document key => merged tags, including those inherited from provider default_tags."
 value = { for k, d in aws_ssm_document.this: k => d.tags_all }
}

###############################################################################
# State Manager associations
###############################################################################

output "association_ids" {
 description = "Map of association key => association_id. Consumed by audit / drift-detection references."
 value = { for k, a in aws_ssm_association.this: k => a.association_id }
}

output "association_arns" {
 description = "Map of association key => association ARN."
 value = { for k, a in aws_ssm_association.this: k => a.arn }
}

output "association_tags_all" {
 description = "Map of association key => merged tags, including those inherited from provider default_tags."
 value = { for k, a in aws_ssm_association.this: k => a.tags_all }
}

###############################################################################
# Patch Manager — baselines
###############################################################################

output "patch_baseline_ids" {
 description = "Map of baseline key => patch baseline id. Consumed by aws_ssm_patch_group registration and Patch Manager console cross-reference."
 value = { for k, b in aws_ssm_patch_baseline.this: k => b.id }
}

output "patch_baseline_arns" {
 description = "Map of baseline key => patch baseline ARN."
 value = { for k, b in aws_ssm_patch_baseline.this: k => b.arn }
}

output "patch_baseline_tags_all" {
 description = "Map of baseline key => merged tags, including those inherited from provider default_tags."
 value = { for k, b in aws_ssm_patch_baseline.this: k => b.tags_all }
}

###############################################################################
# Patch Manager — patch group registrations
#
# Not taggable; no arn attribute in the provider schema.
###############################################################################

output "patch_group_ids" {
 description = "Map of patch group key => id (\"<patch_group>,<baseline_id>\"). aws_ssm_patch_group is not taggable and has no arn."
 value = { for k, g in aws_ssm_patch_group.this: k => g.id }
}

###############################################################################
# Maintenance windows
#
# aws_ssm_maintenance_window has no arn attribute in the current provider
# schema.
###############################################################################

output "maintenance_window_ids" {
 description = "Map of window key => maintenance window id. Consumed by aws_ssm_maintenance_window_target / _task and tf-mod-aws-cloudwatch-alarm (window compliance). No arn attribute is exposed by this resource."
 value = { for k, w in aws_ssm_maintenance_window.this: k => w.id }
}

output "maintenance_window_tags_all" {
 description = "Map of window key => merged tags, including those inherited from provider default_tags."
 value = { for k, w in aws_ssm_maintenance_window.this: k => w.tags_all }
}

###############################################################################
# Maintenance window targets
#
# Not taggable; no arn attribute in the provider schema.
###############################################################################

output "maintenance_window_target_ids" {
 description = "Map of target key => maintenance window target id. aws_ssm_maintenance_window_target is not taggable and has no arn."
 value = { for k, t in aws_ssm_maintenance_window_target.this: k => t.id }
}

###############################################################################
# Maintenance window tasks
#
# Not taggable despite exposing an arn attribute.
###############################################################################

output "maintenance_window_task_ids" {
 description = "Map of task key => maintenance window task id."
 value = { for k, t in aws_ssm_maintenance_window_task.this: k => t.id }
}

output "maintenance_window_task_arns" {
 description = "Map of task key => maintenance window task ARN. aws_ssm_maintenance_window_task is not taggable despite exposing an arn."
 value = { for k, t in aws_ssm_maintenance_window_task.this: k => t.arn }
}
