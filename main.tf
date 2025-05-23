module "Data_Ingestion" {
  source      = "./modules/Data_Ingestion"
  bucket_name = "${var.bucket_name}-${random_id.suffix.hex}"
  region      = var.region
}

resource "random_id" "suffix" {
  byte_length = 4
}

