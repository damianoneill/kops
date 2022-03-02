#!/bin/bash

: "${SCRIPT_VERSION:=v1.0.0}"

: "${AWS_PROFILE:=default}"
: "${KOPS_USER:=kops}"
: "${KOPS_GROUP:=kops}"
: "${S3_BUCKET_PREFIX:=prefix-example}"
: "${S3_BUCKET:=${S3_BUCKET_PREFIX}-com-state-store}"
: "${KOPS_STATE_STORE:=s3://${S3_BUCKET_PREFIX}-com-state-store}"
: "${OUTPUT_DIR:=output}"
: "${TERRAFORM_DIR:=terraform}"
if [ -f "${OUTPUT_DIR}/access-key.json" ]; then
    EXISTING_ACCESS_KEY=$(jq -r .AccessKey.AccessKeyId <${OUTPUT_DIR}/${S3_BUCKET_PREFIX}-access-key.json)
else
    EXISTING_ACCESS_KEY=""
fi
: "${ACCESS_KEY:=${EXISTING_ACCESS_KEY}}"

: "${AWS_ACCOUNT_ID:=$(aws sts get-caller-identity | jq -r ".Account")}"
: "${REGION:=$(aws configure get region)}"

# cluster config
: "${CLUSTER_ID:=${S3_BUCKET_PREFIX}}"
: "${CLUSTER_NAME:=${CLUSTER_ID}.k8s.local}" # .k8s.local == https://kops.sigs.k8s.io/gossip/
: "${CLUSTER_ZONES:=us-west-2a}"
: "${NODE_COUNT:=2}"
: "${MASTER_SIZE:=c5.large}"
: "${NODE_SIZE:=m5.large}"
: "${SSH_PUBLIC_KEY:=~/.ssh/id_rsa.pub}"
: "${CLOUD_LABELS:=Stack=Test}"
: "${RESTRICTED_CIDR:=0.0.0.0/0}" # for multiple CIDR, comma seperated should be used
: "${KOPS_STATE_STORE:=s3\:\/\/${S3_BUCKET}}"

# use for ssh key-pair
: "${KEY_NAME:=${CLUSTER_ID}}"

function showVersion() {
    echo "Script Version: $SCRIPT_VERSION"
}

function promptyn() {
    while true; do
        read -r -p "$1 " yn
        case $yn in
        [Yy]*) return 0 ;;
        [Nn]*) return 1 ;;
        *) echo "Please answer yes or no." ;;
        esac
    done
}

function create-group() {
    if aws --profile ${AWS_PROFILE} iam list-groups | jq -e "(.Groups[] | .GroupName | select(.==\"${KOPS_GROUP}\"))" &>/dev/null; then
        echo ">>> group ${KOPS_GROUP} already exists"
    else
        echo ">>> creating group ${KOPS_GROUP}"
        aws --profile ${AWS_PROFILE} iam create-group --group-name ${KOPS_GROUP} >${OUTPUT_DIR}/${S3_BUCKET_PREFIX}-group.json
        attach-group-policy
    fi
}

function attach-group-policy() {
    aws --profile ${AWS_PROFILE} iam attach-group-policy --policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess --group-name ${KOPS_GROUP}
    aws --profile ${AWS_PROFILE} iam attach-group-policy --policy-arn arn:aws:iam::aws:policy/AmazonRoute53FullAccess --group-name ${KOPS_GROUP}
    aws --profile ${AWS_PROFILE} iam attach-group-policy --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess --group-name ${KOPS_GROUP}
    aws --profile ${AWS_PROFILE} iam attach-group-policy --policy-arn arn:aws:iam::aws:policy/IAMFullAccess --group-name ${KOPS_GROUP}
    aws --profile ${AWS_PROFILE} iam attach-group-policy --policy-arn arn:aws:iam::aws:policy/AmazonVPCFullAccess --group-name ${KOPS_GROUP}
    aws --profile ${AWS_PROFILE} iam attach-group-policy --policy-arn arn:aws:iam::aws:policy/AmazonSQSFullAccess --group-name ${KOPS_GROUP}
    aws --profile ${AWS_PROFILE} iam attach-group-policy --policy-arn arn:aws:iam::aws:policy/AmazonEventBridgeFullAccess --group-name ${KOPS_GROUP}
}

function create-user() {
    if aws --profile ${AWS_PROFILE} iam list-users | jq -e "(.Users[] | .UserName | select(.==\"${KOPS_USER}\"))" &>/dev/null; then
        echo ">>> user ${KOPS_USER} already exists"
    else
        echo ">>> creating user ${KOPS_USER}"
        aws --profile ${AWS_PROFILE} iam create-user --user-name ${KOPS_USER} >${OUTPUT_DIR}/${S3_BUCKET_PREFIX}-user.json
        aws --profile ${AWS_PROFILE} iam add-user-to-group --user-name ${KOPS_USER} --group-name ${KOPS_GROUP}
        aws --profile ${AWS_PROFILE} iam create-access-key --user-name ${KOPS_USER} >${OUTPUT_DIR}/${S3_BUCKET_PREFIX}-access-key.json
    fi
}

function create-bucket() {
    if aws s3api head-bucket --bucket "$S3_BUCKET" 2>/dev/null; then
        echo ">>> bucket ${S3_BUCKET} already exists"
    else
        echo ">>> creating bucket ${S3_BUCKET}"
        aws --profile ${AWS_PROFILE} s3api create-bucket \
            --bucket ${S3_BUCKET} \
            --region us-east-1 >${OUTPUT_DIR}/${S3_BUCKET_PREFIX}-bucket.json
        aws --profile ${AWS_PROFILE} s3api put-bucket-versioning \
            --bucket ${S3_BUCKET} \
            --versioning-configuration Status=Enabled
        aws --profile ${AWS_PROFILE} s3api put-bucket-encryption \
            --bucket ${S3_BUCKET} \
            --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
    fi
}

# currently not used
function create-key-pair() {
    if aws --profile ${AWS_PROFILE} ec2 describe-key-pairs | jq -e "(.KeyPairs[] | .KeyName | select(.==\"${KEY_NAME}\"))" &>/dev/null; then
        echo ">>> key-pair ${KEY_NAME} already exists"
    else
        echo ">>> creating key-pair ${KEY_NAME}"
        aws --profile ${AWS_PROFILE} ec2 create-key-pair \
            --key-name ${KEY_NAME} >${OUTPUT_DIR}/${S3_BUCKET_PREFIX}-${KEY_NAME}.pem
    fi
}

function add-resources() {
    if promptyn ">>> do you want to create the user ${KOPS_USER} with group ${KOPS_GROUP}, and a S3 state bucket ${S3_BUCKET}?"; then
        mkdir -p "${OUTPUT_DIR}"
        create-group
        create-user
        create-bucket
    else
        exit
    fi
}

function create-terraform() {
    echo ">> create terraform configuration for cluster ${CLUSTER_NAME} in zones ${CLUSTER_ZONES} with ${NODE_COUNT} nodes, with bucket ${S3_BUCKET}"
    mkdir -p ${TERRAFORM_DIR}
    kops create cluster ${CLUSTER_NAME} \
        --zones=${CLUSTER_ZONES} \
        --node-count=${NODE_COUNT} \
        --state=s3://${S3_BUCKET} \
        --node-size ${NODE_SIZE} \
        --master-size ${MASTER_SIZE} \
        --ssh-public-key ${SSH_PUBLIC_KEY} \
        --cloud-labels=${CLOUD_LABELS} \
        --admin-access=${RESTRICTED_CIDR} \
        --out=${TERRAFORM_DIR} \
        --target=terraform
}

function create-cluster() {
    echo ">> create configuration for cluster ${CLUSTER_NAME} in zones ${CLUSTER_ZONES} with ${NODE_COUNT} nodes, with bucket ${S3_BUCKET}"
    kops create cluster ${CLUSTER_NAME} \
        --zones=${CLUSTER_ZONES} \
        --node-count=${NODE_COUNT} \
        --state=s3://${S3_BUCKET} \
        --node-size ${NODE_SIZE} \
        --master-size ${MASTER_SIZE} \
        --ssh-public-key ${SSH_PUBLIC_KEY} \
        --cloud-labels=${CLOUD_LABELS} \
        --admin-access=${RESTRICTED_CIDR}
    # --dry-run \
    # -oyaml >${OUTPUT_DIR}/${S3_BUCKET_PREFIX}-kops-create-cluster-config.yaml

    if promptyn ">>> do you want to create cluster ${CLUSTER_NAME} in zones ${CLUSTER_ZONES} with ${NODE_COUNT} nodes, with bucket ${S3_BUCKET}?"; then
        kops update cluster ${CLUSTER_NAME} \
            --state s3://${S3_BUCKET} \
            --yes
        echo ">>> sleeping for 10 seconds" && sleep 10
        kops export kubecfg --admin --state "${KOPS_STATE_STORE}"
        kops validate cluster --wait 10m --state "${KOPS_STATE_STORE}"
    else
        exit
    fi
}

function delete-cluster() {
    if promptyn ">>> do you want to delete cluster ${CLUSTER_NAME} in zones ${CLUSTER_ZONES} with ${NODE_COUNT} nodes, with bucket ${S3_BUCKET}?"; then
        kops delete cluster ${CLUSTER_NAME} \
            --state s3://${S3_BUCKET} \
            --yes
    else
        exit
    fi
}

function remove-resources() {
    if promptyn ">>> do you want to delete the user ${KOPS_USER}, the group ${KOPS_GROUP} and the bucket ${S3_BUCKET_PREFIX}-com-state-store?"; then
        if aws s3api head-bucket --bucket "$S3_BUCKET" 2>/dev/null; then
            echo ">>> deleting bucket ${S3_BUCKET}"
            aws --profile ${AWS_PROFILE} s3api delete-bucket \
                --bucket "${S3_BUCKET}" \
                --region us-east-1
        else
            echo ">>> bucket ${S3_BUCKET} does not exist"
        fi
        if aws --profile ${AWS_PROFILE} iam list-users | jq -e "(.Users[] | .UserName | select(.==\"${KOPS_USER}\"))" &>/dev/null; then
            if aws --profile ${AWS_PROFILE} iam list-access-keys --user-name ${KOPS_USER} | jq -e "(.AccessKeyMetadata[] | .AccessKeyId | select(.==\"${ACCESS_KEY}\"))" &>/dev/null; then
                echo ">>> deleting access key ${ACCESS_KEY}"
                aws --profile ${AWS_PROFILE} iam delete-access-key --user-name ${KOPS_USER} --access-key ${ACCESS_KEY}
            else
                echo ">>> access key ${ACCESS_KEY} does not exist"
            fi
        else
            echo ">>> user ${KOPS_USER} does not exist, cannot list access keys"
        fi
        if aws --profile ${AWS_PROFILE} iam list-users | jq -e "(.Users[] | .UserName | select(.==\"${KOPS_USER}\"))" &>/dev/null; then
            if aws --profile ${AWS_PROFILE} iam list-groups | jq -e "(.Groups[] | .GroupName | select(.==\"${KOPS_GROUP}\"))" &>/dev/null; then
                echo ">>> removing user ${KOPS_USER} from group ${KOPS_GROUP}"
                aws --profile ${AWS_PROFILE} iam remove-user-from-group --user-name ${KOPS_USER} --group-name ${KOPS_GROUP}
            else
                echo ">>> cannot remove user ${KOPS_USER} from group ${KOPS_GROUP}, group ${KOPS_GROUP} does not exist"
            fi
        else
            echo ">>> user ${KOPS_USER} does not exist, cannot be removed from group ${KOPS_GROUP}"
        fi
        if aws --profile ${AWS_PROFILE} iam list-users | jq -e "(.Users[] | .UserName | select(.==\"${KOPS_USER}\"))" &>/dev/null; then
            echo ">>> deleting user ${KOPS_USER}"
            aws --profile ${AWS_PROFILE} iam delete-user --user-name ${KOPS_USER}
        else
            echo ">>> user ${KOPS_USER} does not exist, cannot be deleted"
        fi
        if aws --profile ${AWS_PROFILE} iam list-groups | jq -e "(.Groups[] | .GroupName | select(.==\"${KOPS_GROUP}\"))" &>/dev/null; then
            echo ">>> detaching group polices and deleting group ${KOPS_GROUP}"
            aws --profile ${AWS_PROFILE} iam detach-group-policy --policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess --group-name ${KOPS_GROUP}
            aws --profile ${AWS_PROFILE} iam detach-group-policy --policy-arn arn:aws:iam::aws:policy/AmazonRoute53FullAccess --group-name ${KOPS_GROUP}
            aws --profile ${AWS_PROFILE} iam detach-group-policy --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess --group-name ${KOPS_GROUP}
            aws --profile ${AWS_PROFILE} iam detach-group-policy --policy-arn arn:aws:iam::aws:policy/IAMFullAccess --group-name ${KOPS_GROUP}
            aws --profile ${AWS_PROFILE} iam detach-group-policy --policy-arn arn:aws:iam::aws:policy/AmazonVPCFullAccess --group-name ${KOPS_GROUP}
            aws --profile ${AWS_PROFILE} iam detach-group-policy --policy-arn arn:aws:iam::aws:policy/AmazonSQSFullAccess --group-name ${KOPS_GROUP}
            aws --profile ${AWS_PROFILE} iam detach-group-policy --policy-arn arn:aws:iam::aws:policy/AmazonEventBridgeFullAccess --group-name ${KOPS_GROUP}
            aws --profile ${AWS_PROFILE} iam delete-group --group-name ${KOPS_GROUP}
        else
            echo ">>> group ${KOPS_GROUP} does not exist, cannot be deleted"
        fi
    else
        exit
    fi
}

function export-kube-config() {
    kops export kubecfg --admin --state "${KOPS_STATE_STORE}"
}

function helpfunction() {
    echo "kops-aws.sh - kOpS AWS Setup

    Usage: kops-aws.sh -h
           kops-aws.sh -a -c"
    echo ""
    echo "      -h    show this help message"
    echo "      -v    show Version"
    echo "      -a    add the kOps user, group and bucket"
    echo "      -c    create the cluster"
    echo "      -t    create the terraform configuration"
    echo "      -k    export kubecfg"
    echo "      -d    delete the cluster"
    echo "      -r    remove the kOps user, group and bucket"
    echo ""
}

if [ $# -eq 0 ]; then
    helpfunction
    exit 1
fi

while getopts "hvackdrt-:" OPT; do
    if [ "$OPT" = "-" ]; then   # long option: reformulate OPT and OPTARG
        OPT="${OPTARG%%=*}"     # extract long option name
        OPTARG="${OPTARG#$OPT}" # extract long option argument (may be empty)
        OPTARG="${OPTARG#=}"    # if long option argument, remove assigning `=`
    fi
    case $OPT in
    h)
        helpfunction
        ;;
    v)
        showVersion
        ;;
    a)
        add-resources
        ;;
    c)
        create-cluster
        ;;
    t)
        create-terraform
        ;;
    k)
        export-kube-config
        ;;
    d)
        delete-cluster
        ;;
    r)
        remove-resources
        ;;
    *)
        echo "$(basename "${0}"):usage: [-a] | [-c] | [-t] | [-k] | [-d] | [-r]"
        exit 1 # Command to come out of the program with status 1
        ;;
    esac
done
