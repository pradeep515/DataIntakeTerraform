#/bin/sh
rm -f lambda_function.zip
zip -r lambda_function.zip lambda_function.py boto3
