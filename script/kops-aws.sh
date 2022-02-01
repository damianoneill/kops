#!/bin/bash

: "${SCRIPT_VERSION:=v1.0.0}"

: "${AWS_PROFILE:=default}"
: "${KOPS_USER:=kops}"
: "${KOPS_GROUP:=kops}"
: "${S3_BUCKET_PREFIX:=prefix-example}"
: "${S3_BUCKET:=${S3_BUCKET_PREFIX}-com-state-store}"
: "${CLUSTER_NAME:=myfirstcluster.k8s.local}" # .k8s.local == https://kops.sigs.k8s.io/gossip/
: "${KOPS_STATE_STORE:=s3://${S3_BUCKET_PREFIX}-com-state-store}"
: "${OUTPUT_DIR:=output}"
if [ -f "${OUTPUT_DIR}/access-key.json" ]; then
    EXISTING_ACCESS_KEY=$(jq -r .AccessKey.AccessKeyId <${OUTPUT_DIR}/access-key.json)
else
    EXISTING_ACCESS_KEY=""
fi
: "${ACCESS_KEY:=${EXISTING_ACCESS_KEY}}"

function showVersion() {
    echo "Script Version: $SCRIPT_VERSION"
}

promptyn() {
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
        aws --profile ${AWS_PROFILE} iam create-group --group-name ${KOPS_GROUP} >${OUTPUT_DIR}/.group
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
        aws --profile ${AWS_PROFILE} iam create-user --user-name ${KOPS_USER} >${OUTPUT_DIR}/user.json
        aws --profile ${AWS_PROFILE} iam add-user-to-group --user-name ${KOPS_USER} --group-name ${KOPS_GROUP}
        aws --profile ${AWS_PROFILE} iam create-access-key --user-name ${KOPS_USER} >${OUTPUT_DIR}/access-key.json
    fi
}

function create-bucket() {
    if aws s3api head-bucket --bucket "$S3_BUCKET" 2>/dev/null; then
        echo ">>> bucket ${S3_BUCKET} already exists"
    else
        echo ">>> creating bucket ${S3_BUCKET}"
        aws --profile ${AWS_PROFILE} s3api create-bucket \
            --bucket ${S3_BUCKET} \
            --region us-east-1 >${OUTPUT_DIR}/bucket.json
        aws --profile ${AWS_PROFILE} s3api put-bucket-versioning \
            --bucket ${S3_BUCKET} \
            --versioning-configuration Status=Enabled
        aws --profile ${AWS_PROFILE} s3api put-bucket-encryption \
            --bucket ${S3_BUCKET} \
            --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
    fi
}

function init() {
    if promptyn ">>> do you want to create the user ${KOPS_USER} with group ${KOPS_GROUP} and bucket ${S3_BUCKET}?"; then
        mkdir -p "${OUTPUT_DIR}"
        create-group
        create-user
        create-bucket
    else
        exit
    fi
}

function create-cluster() {
    echo "create cluster"
}

function delete() {
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

function helpfunction() {
    echo "kops-aws.sh - kOpS AWS Setup

    Usage: kops-aws.sh -h
           kops-aws.sh -i -c"
    echo ""
    echo "      -h    Show this help message"
    echo "      -v    Show Version"
    echo "      -i    Create the kOps user, group and bucket"
    echo "      -c    Create the cluster"
    echo "      -d    Delete all the created resources"
    echo ""
}

if [ $# -eq 0 ]; then
    helpfunction
    exit 1
fi

while getopts "hvicd-:" OPT; do
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
    i)
        init
        ;;
    c)
        create-cluster
        ;;
    d)
        delete
        ;;
    *)
        echo "$(basename "${0}"):usage: [-c] | [-d] | [-b]"
        exit 1 # Command to come out of the program with status 1
        ;;
    esac
done
