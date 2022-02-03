# kOps

![kOps Deployment](images/kops-deployment.png)

## Installation

This project used [adsf](http://asdf-vm.com/manage/configuration.html#tool-versions) to provision the appropriate tooling and uses a [.tool-versions](.tool-versions) file to explicitly set the versions.

```shell
asdf install
```

This will install kops, awscli and jq. **Note** that jq is used to parse the response from some of the aws commands, it is therefore assumed that your credential file is set up to output json

```shell
cat ~/.aws/credentials
[your-profile]
output = json
region = us-west-2
aws_access_key_id = XXXXX
aws_secret_access_key = XXXXX
```

## Variables

The script includes a set of variables that can be overriden on the command line.  See below for the list and an example. 

```shell
: "${AWS_PROFILE:=default}"
: "${KOPS_USER:=kops}"
: "${KOPS_GROUP:=kops}"
: "${S3_BUCKET_PREFIX:=prefix-example}"
: "${S3_BUCKET:=${S3_BUCKET_PREFIX}-com-state-store}"
: "${KOPS_STATE_STORE:=s3://${S3_BUCKET_PREFIX}-com-state-store}"
: "${OUTPUT_DIR:=output}"
if [ -f "${OUTPUT_DIR}/access-key.json" ]; then
    EXISTING_ACCESS_KEY=$(jq -r .AccessKey.AccessKeyId <${OUTPUT_DIR}/access-key.json)
else
    EXISTING_ACCESS_KEY=""
fi
: "${ACCESS_KEY:=${EXISTING_ACCESS_KEY}}"

# cluster config
: "${CLUSTER_ID:=myfirstcluster}"
: "${CLUSTER_NAME:=${CLUSTER_ID}.k8s.local}" # .k8s.local == https://kops.sigs.k8s.io/gossip/
: "${CLUSTER_ZONES:=us-west-2a}"
: "${NODE_COUNT:=2}"
: "${MASTER_SIZE:=c5.large}"
: "${NODE_SIZE:=m5.large}"
: "${SSH_PUBLIC_KEY:=~/.ssh/id_rsa.pub}"
: "${CLOUD_LABELS:=Stack=Test}"
: "${RESTRICTED_CIDR:=0.0.0.0/0}"
: "${KOPS_STATE_STORE:=s3\:\/\/${S3_BUCKET}}"
: "${KEY_NAME:=${CLUSTER_ID}}"
```
And an example of overriding some variables. 

```sh
AWS_PROFILE=galileo S3_BUCKET_PREFIX=galileo ./script/kops-aws.sh -a -c
```
## Security Credentials

kOps uses the Go AWS SDK to register security credentials. This [AWS article](https://docs.aws.amazon.com/sdk-for-go/v1/developer-guide/configuring-sdk.html#specifying-credentials) describes how to configure settings for service clients.

In order to use kOps to build clusters in AWS we will create a dedicated IAM user for kOps.

The kOps user will require the following IAM permissions to function properly:

```
AmazonEC2FullAccess
AmazonRoute53FullAccess
AmazonS3FullAccess
IAMFullAccess
AmazonVPCFullAccess
AmazonSQSFullAccess
AmazonEventBridgeFullAccess
```

These policies will be attached to the IAM group in the script.

## Usage

```sh
kops-aws.sh - kOpS AWS Setup

    Usage: kops-aws.sh -h
           kops-aws.sh -a -c

      -h    Show this help message
      -v    Show Version
      -a    Add the kOps user, group and bucket
      -c    Create the cluster
      -d    Delete the cluster
      -r    Remove the kOps user, group and bucket

```

### Add the created resources

First time running this project you need to create the kOps IAM user and its group and to define the state bucket, run the following script, ensure that you bucket-prefix is globally unique.

```sh
AWS_PROFILE=<your-profile> S3_BUCKET_PREFIX=<bucket-prefix-globally-unique> ./script/kops-aws.sh -a
```

For debugging purposes, the output from the commands are stored in ./output folder, including the access-key created for the iam user.

After the user/group/bucket is created, then the cluster can be created.

### Create Kubernetes Cluster

**Note** In this example we will be deploying our cluster to the us-west-2 region.

```sh
AWS_PROFILE=<your-profile> S3_BUCKET_PREFIX=<bucket-prefix-globally-unique> ./scripts/kops-aws.sh -c
```

### Delete Kubernetes Cluster

**Note** In this example we will be deploying our cluster to the us-west-2 region.

```sh
AWS_PROFILE=<your-profile> S3_BUCKET_PREFIX=<bucket-prefix-globally-unique> ./scripts/kops-aws.sh -d
```

### Remove the created resources

When you no longer need kOps you can delete the kOps IAM user, group and bucket by running the following script

```sh
AWS_PROFILE=<your-profile> S3_BUCKET_PREFIX=<bucket-prefix-globally-unique> ./scripts/kops-aws.sh -r
```
