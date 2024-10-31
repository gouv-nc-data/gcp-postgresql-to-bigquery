# gcp-postgresql-to-bigquery

Permet de migrer automatiquement des tables on premise de postgresql vers Bigquery sans spécifier le schéma et sans créer les tables au préalable.  
Il faut cependant créer le dataset en amont.

Pour permettre l'exécution du job il faut demander aux DBA de définir cette conf :
```
ALTER ROLE user IN DATABASE schema
    SET search_path TO schema;
```
