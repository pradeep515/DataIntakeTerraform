import pandas as pd
df = pd.read_csv("/Users/pradeep/Documents/Tendo/TestProject/DataIntakeTerraform/test_files/test_valid.csv")
from lambda_function import validate_csv, transform_data
expected_columns = ["tenant_id", "name", "age", "date"]
df = validate_csv(df, expected_columns)
df = transform_data(df)
print(df)
