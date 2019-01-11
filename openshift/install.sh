#!/usr/bin/env bash

set -e

NC='\033[0m'       # Text Reset
INFO='\033[0;34m'  # Blue
ERROR='\e[0;31m'    # Red


function check_running { # FIXME curl not retying on vm boot (failing quick)...but on second attempt works
  echo -e -n "${INFO}Checking availability of OKD web-console...${NC}"
  local statusCode="$(curl -sLk -w "%{http_code}\\n" -o /dev/null https://openshift.vnet.de:8443 --connect-timeout 2 --retry 10 --retry-delay 5)"
  if [[ ${statusCode} == 200 ]]
  then
    echo -e "${INFO}OK${NC}"
    return
  else
    echo -e "${INFO}FAILED${NC}"
  fi
  false
}

function check_ssh {
  echo -e -n "${INFO}Testing Vagrant SSH settings...${NC}"
  ssh master 'exit 0'
  local status="$?"
  if [[ $status ]]
  then
    echo -e "${INFO}OK${NC}"
  else
    echo -e "${INFO}FAILED...configuring${NC}"
  fi
  return "$status"
}


echo -e -n "${INFO}Checking for Ansible version...${NC}"
if ansible --version | head -n 1 | grep -q 2.6
then
  echo -e "${INFO}OK${NC}"
else
  echo -e "${ERROR}FAILED Only Ansible 2.6 can be used with openshift-ansible${NC}"
fi

echo -e "${INFO}Hypervisor starting and provisioning${NC}"
vagrant up

if ! check_ssh
then
  echo -e "${INFO}Setting up ssh-config for Vagrant${NC}"
  if ! grep -Fxq "Include config-vnet" ~/.ssh/config
  then
      echo "Include config-vnet" >> ~/.ssh/config
  fi
  vagrant ssh-config > ~/.ssh/config-vnet
fi


# only install if Openshift is not installed
if ! check_running
then
  echo -e "${INFO}Running OKD installation${NC}"
  if ! [ -d openshift-ansible ]
  then
    echo -e "${INFO}Checkount openshift-ansible git-repository${NC}"
    git clone https://github.com/openshift/openshift-ansible.git
  fi
  export CHECKOUT=release-3.11
  echo -e "${INFO}Using Branch/Tag '${CHECKOUT}'${NC}"
  cd openshift-ansible && git pull && git checkout ${CHECKOUT} && cd ..

  echo -e "${INFO}Running OKD Prerequisites${NC}"
  ansible-playbook openshift-ansible/playbooks/prerequisites.yml -i openshift-inventory
  echo -e "${INFO}Runnin OKD Installation${NC}"
  ansible-playbook openshift-ansible/playbooks/deploy_cluster.yml -i openshift-inventory
  echo -e "${INFO}Runnin DNS workaround another time, because the installer overwrites the manual change${NC}"
  ansible-playbook fix.yml -i openshift-inventory
  # Run OC tasks as cluster-admin
  echo -e "${INFO}Running additional task with the OKD client${NC}"
  ansible-playbook ansible-after-install.yml -i openshift-inventory
fi

echo -e "${INFO}DONE${NC}"
