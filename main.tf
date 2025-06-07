module "Data_Ingestion" {
  source      = "./modules/Data_Ingestion"
  bucket_name = "${var.bucket_name}-${random_id.suffix.hex}"
  region      = var.region
}

module "Apps_Networking" {
  source      = "./modules/Apps_Networking"
}

resource "random_id" "suffix" {
  byte_length = 4
}