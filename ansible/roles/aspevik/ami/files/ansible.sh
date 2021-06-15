#!/bin/bash

AWS_MAGIC_EC2_IP="169.254.169.254"
AWS_MAGIC_EC2_ENDPOINT="${AWS_MAGIC_EC2_ENDPOINT}/latest/meta-data/spot/instance-action"
INSTANCE_ID=$(curl -fs ${AWS_MAGIC_EC2_IP}/latest/dynamic/instance-identity/document | jq -r .instanceId)
INSTANCE_REGION=$(curl -fs ${AWS_MAGIC_EC2_IP}/latest/dynamic/instance-identity/document | jq -r .region)
INSTANCE_IP=$(curl -fs ${AWS_MAGIC_EC2_IP}/latest/meta-data/public-ipv4)
export AWS_REGION="${INSTANCE_REGION}"

function log() {
  echo "$1"
}


if [ ! -d "/home/asp/.ssh" ]; then
  mkdir /home/asp/.ssh
  # Set up private and public SSH key in order to pull repository
  aws --region "${AWS_REGION}" secretsmanager get-secret-value \
                                          --secret-id /valheim/github-read-private-ssh-key \
                                          --query 'SecretString' --output text > ~/.ssh/id_rsa
  aws --region "${AWS_REGION}" secretsmanager get-secret-value \
                                          --secret-id /valheim/github-read-public-ssh-key \
                                          --query 'SecretString' --output text > ~/.ssh/id_rsa.pub

  chmod 400 ~/.ssh/*
fi

# Pull tags to determine branch of Ansible.
#INSTANCE_TAGS=$(aws --region ${AWS_REGION} ec2 describe-instances --instance-ids ${INSTANCE_ID} | jq ".Reservations[0].Instances[0].Tags")
BASE_DIR=$(dirname "$(realpath -s $0)")
ANSIBLE_REPO="git@github.com:KristianAsp/ansible.git"
ANSIBLE_REPO_DIR="${BASE_DIR}/repository"

log "BASE_DIR: $BASE_DIR"
log "ANSIBLE_REPO: $ANSIBLE_REPO"
log "ANSIBLE_REPO_DIR: $ANSIBLE_REPO_DIR"

# Only clone if it doesn't already exist
if [ ! -d "${ANSIBLE_REPO_DIR}" ]; then
  log "INFO - Cloning Ansible $ANSIBLE_REPO repository to $ANSIBLE_REPO_DIR"
  git clone ${ANSIBLE_REPO} --branch "${ANSIBLE_REF:-main}" "$ANSIBLE_REPO_DIR" > /dev/null 2>&1
  if [ $? -ne 0 ]; then
    log "ERROR - Failed to clone Ansible repository"
    exit 1
  fi
fi

pushd "${ANSIBLE_REPO_DIR}" || exit

# Make sure we've pulled the latest changes and are running an up to date version of the repository and branch.
git fetch origin "${ANSIBLE_REF:-main}" && git checkout -f "${ANSIBLE_REF:-main}" && git pull

# Execute the main playbook in Ansible repository
ansible-playbook \
    --inventory=dynamic-inventory \
    --connection=local \
    --limit $INSTANCE_IP \
    playbooks/main.yml \
    $ANSIBLE_CMD_EXTRA_ARGS \
    -e ansible_python_interpreter=/usr/local/bin

