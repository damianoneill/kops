# kOps

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

## Security Credentials

kOps uses the Go AWS SDK to register security credentials. This [AWS article](https://docs.aws.amazon.com/sdk-for-go/v1/developer-guide/configuring-sdk.html#specifying-credentials) describes how to configure settings for service clients.

In order to use kOps to build clusters in AWS we will create a dedicated IAM user for kOps.

The kops user will require the following IAM permissions to function properly:

```
AmazonEC2FullAccess
AmazonRoute53FullAccess
AmazonS3FullAccess
IAMFullAccess
AmazonVPCFullAccess
AmazonSQSFullAccess
AmazonEventBridgeFullAccess
```

## Usage

First time running this project you need to create the kOps IAM user and its group and to define the state bucket, run the following script, ensure that you bucket-prefix is globally unique.

```sh
AWS_PROFILE=<your-profile> S3_BUCKET_PREFIX=<bucket-prefix-globally-unique> ./script/kops-aws.sh -i
```

For debugging purposes, the output from the commands are stored in [./output](./output) folder, including the access-key created for the iam user.

After the user/group/bucket is created, then the cluster can be created.

TODO

When you no longer need kOps you can delete the kOps IAM user, group and bucket by running the following script

```sh
AWS_PROFILE=<your-profile> S3_BUCKET_PREFIX=<bucket-prefix-globally-unique> ./scripts/kops-aws.sh -d
```
