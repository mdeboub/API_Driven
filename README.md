----------------------------------------------------------------------------------------


## Séquence 2 : Création de l'environnement AWS (LocalStack)
Objectif : Créer l'environnement AWS simulé avec LocalStack
Difficulté : Simple (~5 minutes)

**Installation de l'émulateur LocalStack**

```bash
sudo -i mkdir rep_localstack
```

```bash
sudo -i python3 -m venv ./rep_localstack
```

```bash
sudo -i pip install --upgrade pip && python3 -m pip install localstack && export S3_SKIP_SIGNATURE_VALIDATION=0
```

**Ajout du token LocalStack (obligatoire depuis mars 2026)**

```bash
export LOCALSTACK_AUTH_TOKEN=votre_token_ici
```

> Créez un compte sur https://app.localstack.cloud pour obtenir votre token gratuit.

**Démarrage de LocalStack**

```bash
localstack start -d
```

**Vérification des services disponibles**

```bash
localstack status services
```

**Récupération de l'endpoint AWS**

Dans l'onglet **[PORTS]** de votre Codespace, rendez public le port **4566** — c'est votre endpoint AWS local.

---

## Séquence 3 : Déploiement de l'infrastructure
Objectif : Piloter une instance EC2 via API Gateway
Difficulté : Moyen/Difficile (~2h)

**Installation des outils AWS**

```bash
pip install awscli awscli-local
```

**Configuration AWS (credentials factices pour LocalStack)**

```bash
aws configure set aws_access_key_id test
aws configure set aws_secret_access_key test
aws configure set region us-east-1
```

**Récupération d'une AMI disponible**

```bash
awslocal ec2 describe-images --query 'Images[0].ImageId' --output text
```

**Création de l'instance EC2**

```bash
awslocal ec2 run-instances --image-id ami-03cf127a --instance-type t2.micro --count 1
```

**Récupération de l'ID de l'instance**

```bash
INSTANCE_ID=$(awslocal ec2 describe-instances --query 'Reservations[0].Instances[0].InstanceId' --output text)
echo "Instance ID: $INSTANCE_ID"
```

**Création de la fonction Lambda**

```bash
mkdir -p lambda && cat > lambda/handler.py << 'EOF'
import boto3
import json
import os

def handler(event, context):
    ec2 = boto3.client(
        'ec2',
        endpoint_url='http://172.17.0.1:4566',
        region_name='us-east-1',
        aws_access_key_id='test',
        aws_secret_access_key='test'
    )
    action = event.get('action', 'status')
    instance_id = event.get('instance_id', os.environ.get('INSTANCE_ID', ''))
    if action == 'start':
        ec2.start_instances(InstanceIds=[instance_id])
        return {'statusCode': 200, 'body': json.dumps({'message': f'Instance {instance_id} demarree'})}
    elif action == 'stop':
        ec2.stop_instances(InstanceIds=[instance_id])
        return {'statusCode': 200, 'body': json.dumps({'message': f'Instance {instance_id} stoppee'})}
    else:
        response = ec2.describe_instances(InstanceIds=[instance_id])
        state = response['Reservations'][0]['Instances'][0]['State']['Name']
        return {'statusCode': 200, 'body': json.dumps({'instance_id': instance_id, 'state': state})}
EOF
```

**Zip et déploiement de la Lambda**

```bash
cd lambda && zip handler.zip handler.py && cd ..
```

```bash
awslocal lambda create-function \
  --function-name ec2-controller \
  --runtime python3.11 \
  --handler handler.handler \
  --zip-file fileb://lambda/handler.zip \
  --role arn:aws:iam::000000000000:role/lambda-role \
  --environment Variables={INSTANCE_ID=$INSTANCE_ID}
```

**Création de l'API Gateway**

```bash
API_ID=$(awslocal apigateway create-rest-api --name 'EC2Controller' --query 'id' --output text)
echo "API_ID: $API_ID"
```

```bash
ROOT_ID=$(awslocal apigateway get-resources --rest-api-id $API_ID --query 'items[0].id' --output text)

RESOURCE_ID=$(awslocal apigateway create-resource \
  --rest-api-id $API_ID \
  --parent-id $ROOT_ID \
  --path-part ec2 \
  --query 'id' --output text)

awslocal apigateway put-method \
  --rest-api-id $API_ID \
  --resource-id $RESOURCE_ID \
  --http-method POST \
  --authorization-type NONE

awslocal apigateway put-integration \
  --rest-api-id $API_ID \
  --resource-id $RESOURCE_ID \
  --http-method POST \
  --type AWS_PROXY \
  --integration-http-method POST \
  --uri arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/arn:aws:lambda:us-east-1:000000000000:function:ec2-controller/invocations

awslocal apigateway create-deployment \
  --rest-api-id $API_ID \
  --stage-name prod
```

**Tests de l'API**

Vérifier le statut de l'instance :

```bash
curl -X POST \
  "http://localhost:4566/restapis/$API_ID/prod/_user_request_/ec2" \
  -H "Content-Type: application/json" \
  -d "{\"action\": \"status\", \"instance_id\": \"$INSTANCE_ID\"}"
```

Stopper l'instance :

```bash
curl -X POST \
  "http://localhost:4566/restapis/$API_ID/prod/_user_request_/ec2" \
  -H "Content-Type: application/json" \
  -d "{\"action\": \"stop\", \"instance_id\": \"$INSTANCE_ID\"}"
```

Démarrer l'instance :

```bash
curl -X POST \
  "http://localhost:4566/restapis/$API_ID/prod/_user_request_/ec2" \
  -H "Content-Type: application/json" \
  -d "{\"action\": \"start\", \"instance_id\": \"$INSTANCE_ID\"}"
```

---

## Séquence 4 : Documentation

### Structure du projet

```
API_Driven/
├── lambda/
│   ├── handler.py        # Fonction Lambda Python
│   └── handler.zip       # Lambda zippée pour déploiement
├── Makefile              # Automatisation complète
└── README.md             # Documentation
```

### ⚡ Lancement rapide (Makefile)

```bash
make all
```

| Commande | Description |
|---|---|
| `make all` | Lance tout (setup + ec2 + lambda + api) |
| `make test-status` | Vérifie le statut de l'instance |
| `make test-stop` | Stoppe l'instance EC2 |
| `make test-start` | Démarre l'instance EC2 |
| `make clean` | Supprime les ressources |

###  Explication technique

**LocalStack** simule les services AWS en local sans compte AWS réel. Tout tourne dans un container Docker sur le port 4566.

**API Gateway** expose un endpoint HTTP POST sur `/ec2` qui déclenche la fonction Lambda.

**Lambda** reçoit l'action (`start`, `stop`, `status`) et l'instance_id, puis appelle l'API EC2 de LocalStack via l'adresse `172.17.0.1:4566` (adresse interne du container Docker).

**EC2** est une instance simulée par LocalStack qui répond aux appels start/stop/describe.

---

