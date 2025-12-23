locals {
  parent_folder_id         = 658965356947 # production folder
  secret-managment-project = "prj-dinum-p-secret-mgnt-aaf4"

  hyphen_ds_name = substr(lower(replace(var.dataset_name, "_", "-")), 0, 24)
  safe_gen_id    = length(var.generation_id) > 0 ? "#${var.generation_id}" : ""

  # Email du Service Account à utiliser (fourni ou créé)
  service_account_email = var.service_account_email != "" ? var.service_account_email : google_service_account.service_account[0].email

  # Nom du bucket GCS pour les fichiers temporaires
  bucket_name = var.bucket_name != "" ? var.bucket_name : google_storage_bucket.bucket_upload[0].name

  # Générer un suffixe unique pour le nom du job
  job_suffix = substr(md5("${var.dataset_name}-${var.schedule}-${var.schema}"), 0, 4)
}


resource "google_service_account" "service_account" {
  count = var.service_account_email == "" ? 1 : 0

  account_id   = "sa-pg2bq-${local.hyphen_ds_name}-${local.job_suffix}"
  display_name = "Service Account created by terraform for ${var.project_id}"
  project      = var.project_id
}

resource "google_project_iam_member" "roles_bindings" {
  for_each = var.service_account_email == "" ? toset([
    "roles/bigquery.dataEditor",
    "roles/bigquery.user",
    "roles/dataproc.editor",
    "roles/dataproc.worker",
    "roles/storage.objectViewer",
    "roles/cloudscheduler.jobRunner"
  ]) : toset([])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${local.service_account_email}"
}


# Permission actAs pour le SA sur lui-même (nécessaire pour Dataproc Serverless) pour "iam.serviceAccounts.actAs" 
resource "google_service_account_iam_member" "sa_act_as" {
  count              = var.service_account_email == "" ? 1 : 0
  service_account_id = google_service_account.service_account[0].name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${local.service_account_email}"
}

# pour "dataproc.workflowTemplates.instantiate"
resource "google_project_iam_member" "dataproc_instantiate" {
  count   = var.service_account_email == "" ? 1 : 0
  project = var.project_id
  role    = "roles/dataproc.editor"
  member  = "serviceAccount:${local.service_account_email}"
}

resource "google_service_account_iam_member" "gce-default-account-iam" {
  count = var.service_account_email == "" ? 1 : 0

  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${local.service_account_email}"
  service_account_id = google_service_account.service_account[0].name
}

####
# Dataproc
####

resource "google_storage_bucket_iam_member" "access_to_script" {
  count = var.service_account_email == "" ? 1 : 0

  bucket = "bucket-prj-dinum-data-templates-66aa"
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${local.service_account_email}"
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

resource "google_storage_bucket" "bucket_upload" {
  count = var.bucket_name == "" ? 1 : 0

  project                     = var.project_id
  name                        = "bucket-${var.dataset_name}-${local.job_suffix}"
  location                    = var.region
  uniform_bucket_level_access = true
}


resource "google_cloud_scheduler_job" "job" {
  project          = var.project_id
  name             = "pg2bq-job-${local.hyphen_ds_name}-${local.job_suffix}"
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
      service_account_email = local.service_account_email
    }
    body = base64encode(
      jsonencode(
        {
          "pysparkBatch" : {
            "jarFileUris" : [
              "gs://bucket-prj-dinum-data-templates-66aa/${var.driver_file_name}"
            ],
            "args" : [
              "--jdbc-url=${data.google_secret_manager_secret_version.jdbc-url-secret.secret_data}",
              "--schema=${var.schema}",
              "--dataset=${var.dataset_name}",
              "--exclude=${var.exclude}",
              "--only=${var.only}",
              "--bucket=${local.bucket_name}"
            ],
            "mainPythonFileUri" : "gs://bucket-prj-dinum-data-templates-66aa/postgresql_to_bigquery.py${local.safe_gen_id}"
          },
          "runtimeConfig" : {
            "version" : "${var.runtimeConfig_version}",
            "properties" : {
              "spark.executor.instances" : "2",
              "spark.driver.cores" : "4",
              "spark.driver.memory" : "9600m",
              "spark.executor.cores" : "4",
              "spark.executor.memory" : "9600m",
              "spark.dynamicAllocation.executorAllocationRatio" : "0.3",
              "spark.hadoop.fs.gs.inputstream.support.gzip.encoding.enable" : "true",
              "spark.sql.parquet.datetimeRebaseModeInWrite" : "LEGACY"
            }
          },
          "environmentConfig" : {
            "executionConfig" : {
              "serviceAccount" : local.service_account_email,
              "subnetworkUri" : "${var.subnetwork_name}",
              "ttl" : "${var.ttl}"
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
