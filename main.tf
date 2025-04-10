locals {
  parent_folder_id         = 658965356947 # production folder
  secret-managment-project = "prj-dinum-p-secret-mgnt-aaf4"

  hyphen_ds_name = substr(lower(replace(var.dataset_name, "_", "-")), 0, 24)
  safe_gen_id    = length(var.generation_id) > 0 ? "#${var.generation_id}" : ""
}

resource "google_bigquery_dataset" "dataset" {
  count = var.create_dataset ? 1 : 0

  project    = var.project_id
  dataset_id = var.dataset_name
  location   = "EU"
}

resource "google_service_account" "service_account" {
  account_id   = "sa-pg2bq-${local.hyphen_ds_name}"
  display_name = "Service Account created by terraform for ${var.project_id}"
  project      = var.project_id
}

resource "google_project_iam_member" "roles_bindings" {
  for_each = toset([
    "roles/bigquery.dataEditor",
    "roles/bigquery.user",
    "roles/dataproc.editor",
    "roles/dataproc.worker",
    "roles/storage.objectViewer",
    "roles/cloudscheduler.jobRunner"
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.service_account.email}"
}


resource "google_project_iam_custom_role" "dataproc-custom-role" {
  project     = var.project_id
  role_id     = "pg2bq_spark_custom_role_${var.dataset_name}"
  title       = "Dataproc Custom Role"
  description = "Role custom pour pouvoir créer des job dataproc depuis scheduler"
  permissions = ["iam.serviceAccounts.actAs", "dataproc.workflowTemplates.instantiate"]
}


resource "google_project_iam_member" "dataflow_custom_worker_bindings" {
  project    = var.project_id
  role       = "projects/${var.project_id}/roles/${google_project_iam_custom_role.dataproc-custom-role.role_id}"
  member     = "serviceAccount:${google_service_account.service_account.email}"
  depends_on = [google_project_iam_custom_role.dataproc-custom-role]
}

resource "google_service_account_iam_member" "gce-default-account-iam" {
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.service_account.email}"
  service_account_id = google_service_account.service_account.name
}

####
# Dataproc
####

resource "google_storage_bucket_iam_member" "access_to_script" {
  bucket = "bucket-prj-dinum-data-templates-66aa"
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.service_account.email}"
}

resource "google_project_service" "api_activation" {
  for_each = toset([
    "cloudscheduler.googleapis.com",
    "dataproc.googleapis.com",
    "secretmanager.googleapis.com"
  ])
  project = var.project_id
  service = each.value

  disable_on_destroy = false
}


data "google_secret_manager_secret_version" "jdbc-url-secret" {
  project = local.secret-managment-project
  secret  = var.jdbc-url-secret-name
}

resource "google_cloud_scheduler_job" "job" {
  project          = var.project_id
  name             = "pg2bq-job-${local.hyphen_ds_name}"
  schedule         = var.schedule
  time_zone        = "Pacific/Noumea"
  attempt_deadline = "320s"

  retry_config {
    retry_count = 1
  }

  http_target {
    http_method = "POST"
    uri         = "https://dataproc.googleapis.com/v1/projects/${var.project_id}/locations/${var.region}/batches/"
    oauth_token {
      service_account_email = google_service_account.service_account.email
    }
    body = base64encode(
      jsonencode(
        {
          "pysparkBatch" : {
            "jarFileUris" : [
              "gs://bucket-prj-dinum-data-templates-66aa/postgresql-42.2.6.jar"
            ],
            "args" : [
              "--jdbc-url=${data.google_secret_manager_secret_version.jdbc-url-secret.secret_data}",
              "--schema=${var.schema}",
              "--dataset=${var.dataset_name}",
              "--exclude=${var.exclude}"
            ],
            "mainPythonFileUri" : "gs://bucket-prj-dinum-data-templates-66aa/postgresql_to_bigquery.py${local.safe_gen_id}"
          },
          "runtimeConfig" : {
            "version" : "2.1",
            "properties" : {
              "spark.executor.instances" : "2",
              "spark.driver.cores" : "4",
              "spark.driver.memory" : "9600m",
              "spark.executor.cores" : "4",
              "spark.executor.memory" : "9600m",
              "spark.dynamicAllocation.executorAllocationRatio" : "0.3",
              "spark.hadoop.fs.gs.inputstream.support.gzip.encoding.enable" : "true"
            }
          },
          "environmentConfig" : {
            "executionConfig" : {
              "serviceAccount" : google_service_account.service_account.email,
              "subnetworkUri" : "${var.subnetwork_name}",
              "ttl": "${var.ttl}"
            }
          }
        }
      )
    )
  }
  depends_on = [google_project_service.api_activation[0]]
}

###############################
# Supervision
###############################
resource "google_monitoring_alert_policy" "errors" {
  display_name = "Errors in logs alert policy on ${var.dataset_name}"
  project      = var.project_id
  combiner     = "OR"
  conditions {
    display_name = "Error condition"
    condition_matched_log {
      filter = "severity=ERROR resource.type=\"cloud_dataproc_batch\""
    }
  }

  notification_channels = var.notification_channels
  alert_strategy {
    notification_rate_limit {
      period = "300s"
    }
    auto_close = "86400s" # 1 jour
  }
}
