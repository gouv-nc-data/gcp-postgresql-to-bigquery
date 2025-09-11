variable "project_id" {
  type        = string
  description = "id du projet"
}

variable "region" {
  type    = string
  default = "europe-west1"
}

variable "group_name" {
  type        = string
  description = "Google groupe associé au projet"
}

variable "schedule" {
  type        = string
  description = "expression cron de schedule du job"
}

variable "jdbc-url-secret-name" {
  type        = string
  description = "nom du secret contenant l'url de connexion jdbc à la BDD"
}

variable "dataset_name" {
  type        = string
  description = "nom du projet"
}

variable "notification_channels" {
  type        = list(string)
  description = "canal de notification pour les alertes sur dataproc"
}

variable "schema" {
  type        = string
  description = "schema contenant les tables à migrer"
}

variable "exclude" {
  type        = string
  description = "liste des tables à ne pas migrer"
  default     = ""
}

variable "mode" {
  type        = string
  description = "type d'upload sur bigquery"
  default     = "overwrite"
}

variable "generation_id" {
  type        = string
  description = "generation id du fichier dans le bucket"
  default     = ""
}

variable "subnetwork_name" {
  type        = string
  description = "subnetwork du job"
  default     = "subnet-for-vpn"
}

variable "ttl" {
  type        = string
  description = "Durée maximum d'un job en seconde, https://cloud.google.com/dataproc-serverless/docs/quickstarts/spark-batch?hl=fr#dataproc_serverless_create_batch_workload-api"
  default     = "14400s"
}

variable "create_dataset" {
  type        = bool
  description = "Créer le dataset si il n'existe pas"
  default     = false
}

variable "runtimeConfig_version" {
  type        = string
  description = "Version de la configuration runtime"
  default     = "2.3"

}

variable "driver_file_name" {
  type        = string
  description = "Nom du fichier driver"
  default     = "postgresql-42.7.7.jar"

}

variable "service_account_email" {
  type        = string
  description = "Email du Service Account à utiliser. Si non spécifié, un nouveau Service Account sera créé."
  default     = ""
}

variable "only" {
  type        = string
  description = "Liste des tables à migrer, séparées par des virgules"
  default     = ""
}
