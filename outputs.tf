output "service_account_email" {
  description = "Email du Service Account utilisé par le module"
  value       = local.service_account_email
}

output "bucket_name" {
  description = "Nom du bucket GCS pour les fichiers temporaires"
  value       = local.bucket_name
}
