#!/usr/bin/env bash

set -e

NC='\033[0m'       # Text Reset
INFO='\033[0;34m'  # Blue


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


echo -e "${INFO}Hypervisor starting and provisioning${NC}"
vagrant up

if ! check_ssh
then
  echo -e "${INFO}Setting up ssh-config for Vagrant${NC}"
  if [ ! -f ~/.ssh/config ]
  then
     ~/.ssh/config
  fi
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
  cd openshift-ansible && git checkout openshift-ansible-3.10.49-1 && cd ..
  ansible-playbook openshift-ansible/playbooks/prerequisites.yml -i openshift-inventory
  ansible-playbook openshift-ansible/playbooks/deploy_cluster.yml -i openshift-inventory
  # Fix broken DNS
  ansible-playbook fix.yml -i openshift-inventory
  # Run OC tasks as cluster-admin
  echo -e "${INFO}Running additional task with the OKD client${NC}"
  ansible-playbook ansible-after-install.yml -i openshift-inventory
  # Linkerd 2
  echo -e "${INFO}Installing Linkerd ServiceMesh${NC}"
  oc login --username=admin --password=admin
  linkerd check --pre
  linkerd install | oc apply -f -
  oc adm policy add-scc-to-user privileged -z linkerd-controller -n linkerd
  oc adm policy add-scc-to-user privileged -z linkerd-prometheus -n linkerd
  oc adm policy add-scc-to-user privileged -z default -n linkerd
  linkerd check
fi

echo -e "${INFO}DONE${NC}"
