locals {
  parent_folder_id         = 658965356947 # production folder
  secret-managment-project = "prj-dinum-p-secret-mgnt-aaf4"
}

resource "google_service_account" "service_account" {
  account_id   = "sa-pg2bq-${var.dataset_name}"
  display_name = "Service Account created by terraform for ${var.project_id}"
  project      = var.project_id
}

resource "google_project_iam_member" "bigquery_editor_bindings" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:${google_service_account.service_account.email}"
}

resource "google_project_iam_member" "bigquery_user_bindings" {
  project = var.project_id
  role    = "roles/bigquery.user"
  member  = "serviceAccount:${google_service_account.service_account.email}"
}

resource "google_project_iam_member" "dataflow_worker_bindings" {
  project = var.project_id
  role    = "roles/dataflow.worker"
  member  = "serviceAccount:${google_service_account.service_account.email}"
}

resource "google_project_iam_member" "storage_admin_bindings" {
  project = var.project_id
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${google_service_account.service_account.email}"
}

resource "google_project_iam_custom_role" "dataflow-custom-role" {
  project     = var.project_id
  role_id     = "pg2bq_custom_role_${var.dataset_name}"
  title       = "Dataflow Custom Role"
  description = "Role custom pour pouvoir créer des job dataflow depuis scheduler"
  permissions = ["iam.serviceAccounts.actAs", "dataflow.jobs.create", "storage.objects.create", "storage.objects.delete",
                  "storage.objects.get", "storage.objects.getIamPolicy", "storage.objects.list"]
}


resource "google_project_iam_member" "dataflow_custom_worker_bindings" {
  project    = var.project_id
  role       = "projects/${var.project_id}/roles/${google_project_iam_custom_role.dataflow-custom-role.role_id}"
  member     = "serviceAccount:${google_service_account.service_account.email}"
  depends_on = [google_project_iam_custom_role.dataflow-custom-role]
}

resource "google_service_account_iam_member" "gce-default-account-iam" {
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.service_account.email}"
  service_account_id = google_service_account.service_account.name
}

resource "google_project_iam_member" "cloud_scheduler_runner_bindings" {
  project = var.project_id
  role    = "roles/cloudscheduler.jobRunner"
  member  = "serviceAccount:${google_service_account.service_account.email}"
}
resource "google_project_iam_member" "service_account_bindings_dataflow_admin" {
  project  = var.project_id
  role     = "roles/dataflow.admin"
  member   = "serviceAccount:${google_service_account.service_account.email}"
}

resource "google_project_iam_member" "service_account_bindings_dataflow_worker" {
  project  = var.project_id
  role     = "roles/dataflow.worker"
  member   = "serviceAccount:${google_service_account.service_account.email}"
}

####
# Bucket
####

resource "google_storage_bucket" "bucket" {
  project                     = var.project_id
  name                        = "bucket-pg2bq-${var.dataset_name}"
  location                    = var.region
  storage_class               = "REGIONAL"
  uniform_bucket_level_access = true
  force_destroy               = true
}

####
# Dataflow
####

resource "google_storage_bucket_iam_member" "access_to_script" {
  bucket = "bucket-prj-dinum-data-templates-66aa"
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.service_account.email}"
}

resource "google_project_service" "secretmanagerapi" {
  project = var.project_id
  service = "secretmanager.googleapis.com"
}

resource "google_project_service" "cloudschedulerapi" {
  project = var.project_id
  service = "cloudscheduler.googleapis.com"
}

resource "google_project_service" "dataflowrapi" {
  project = var.project_id
  service = "dataflow.googleapis.com"
}

data "google_secret_manager_secret_version" "jdbc-url-secret" {
  project = local.secret-managment-project
  secret  = var.jdbc-url-secret-name
}

resource "google_cloud_scheduler_job" "job" {
  project          = var.project_id
  name             = "pg2bq-job-${var.dataset_name}"
  schedule         = var.schedule
  time_zone        = "Pacific/Noumea"
  attempt_deadline = "320s"

  retry_config {
    retry_count = 1
  }

  http_target {
    http_method = "POST"
    uri         = "https://dataflow.googleapis.com/v1b3/projects/${var.project_id}/locations/${var.region}/flexTemplates:launch"
    oauth_token {
      service_account_email = google_service_account.service_account.email
    }
    body = base64encode(
      jsonencode(
        {
          launchParameter : {
            jobName : "pg2bq-${var.dataset_name}",
            containerSpecGcsPath : "gs://bucket-prj-dinum-data-templates-66aa/df_postgresql_to_bigquery.json",
            parameters : {
              dataset: var.dataset_name,
              jdbc-url: data.google_secret_manager_secret_version.jdbc-url-secret.secret_data 
              schema: var.schema,
              exclude: var.exclude
              mode: "overwrite"
            },
            environment : {
              numWorkers : 1,
              tempLocation : "gs://${google_storage_bucket.bucket.name}/tmp",
              subnetwork : "regions/${var.region}/subnetworks/subnet-for-vpn",
              serviceAccountEmail: google_service_account.service_account.email,
            }
          }
        }
      )
    )
  }
  depends_on = [google_project_service.cloudschedulerapi]
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
      filter = "severity=ERROR AND resource.type=cloud_dataflow_cluster"
    }
  }

  notification_channels = var.notification_channels
  alert_strategy {
    notification_rate_limit {
      period = "300s"
    }
  }
}
