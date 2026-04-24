.PHONY: all setup ec2 lambda api test-status test-stop test-start clean

all: setup ec2 lambda api

setup:
	pip install awscli awscli-local
	aws configure set aws_access_key_id test
	aws configure set aws_secret_access_key test
	aws configure set region us-east-1

ec2:
	$(eval AMI_ID=$(shell awslocal ec2 describe-images --query 'Images[0].ImageId' --output text))
	awslocal ec2 run-instances --image-id $(AMI_ID) --instance-type t2.micro --count 1

lambda:
	cd lambda && zip handler.zip handler.py && cd ..
	$(eval INSTANCE_ID=$(shell awslocal ec2 describe-instances --query 'Reservations[0].Instances[0].InstanceId' --output text))
	awslocal lambda create-function --function-name ec2-controller --runtime python3.11 --handler handler.handler --zip-file fileb://lambda/handler.zip --role arn:aws:iam::000000000000:role/lambda-role --environment Variables={INSTANCE_ID=$(INSTANCE_ID)} || awslocal lambda update-function-code --function-name ec2-controller --zip-file fileb://lambda/handler.zip

api:
	$(eval API_ID=$(shell awslocal apigateway create-rest-api --name 'EC2Controller' --query 'id' --output text))
	$(eval ROOT_ID=$(shell awslocal apigateway get-resources --rest-api-id $(API_ID) --query 'items[0].id' --output text))
	$(eval RESOURCE_ID=$(shell awslocal apigateway create-resource --rest-api-id $(API_ID) --parent-id $(ROOT_ID) --path-part ec2 --query 'id' --output text))
	awslocal apigateway put-method --rest-api-id $(API_ID) --resource-id $(RESOURCE_ID) --http-method POST --authorization-type NONE
	awslocal apigateway put-integration --rest-api-id $(API_ID) --resource-id $(RESOURCE_ID) --http-method POST --type AWS_PROXY --integration-http-method POST --uri arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/arn:aws:lambda:us-east-1:000000000000:function:ec2-controller/invocations
	awslocal apigateway create-deployment --rest-api-id $(API_ID) --stage-name prod

test-status:
	$(eval API_ID=$(shell awslocal apigateway get-rest-apis --query 'items[0].id' --output text))
	$(eval INSTANCE_ID=$(shell awslocal ec2 describe-instances --query 'Reservations[0].Instances[0].InstanceId' --output text))
	curl -X POST "http://localhost:4566/restapis/$(API_ID)/prod/_user_request_/ec2" -H "Content-Type: application/json" -d "{\"action\": \"status\", \"instance_id\": \"$(INSTANCE_ID)\"}"

test-stop:
	$(eval API_ID=$(shell awslocal apigateway get-rest-apis --query 'items[0].id' --output text))
	$(eval INSTANCE_ID=$(shell awslocal ec2 describe-instances --query 'Reservations[0].Instances[0].InstanceId' --output text))
	curl -X POST "http://localhost:4566/restapis/$(API_ID)/prod/_user_request_/ec2" -H "Content-Type: application/json" -d "{\"action\": \"stop\", \"instance_id\": \"$(INSTANCE_ID)\"}"

test-start:
	$(eval API_ID=$(shell awslocal apigateway get-rest-apis --query 'items[0].id' --output text))
	$(eval INSTANCE_ID=$(shell awslocal ec2 describe-instances --query 'Reservations[0].Instances[0].InstanceId' --output text))
	curl -X POST "http://localhost:4566/restapis/$(API_ID)/prod/_user_request_/ec2" -H "Content-Type: application/json" -d "{\"action\": \"start\", \"instance_id\": \"$(INSTANCE_ID)\"}"

clean:
	awslocal lambda delete-function --function-name ec2-controller || true
	$(eval INSTANCE_ID=$(shell awslocal ec2 describe-instances --query 'Reservations[0].Instances[0].InstanceId' --output text))
	awslocal ec2 terminate-instances --instance-ids $(INSTANCE_ID) || true