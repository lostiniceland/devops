#!/usr/bin/env bash

set -e

NC='\033[0m'       # Text Reset
INFO='\033[0;34m'  # Blue

echo -e "${INFO}Installing Linkerd ServiceMesh${NC}"
oc login --username=admin --password=admin
linkerd check --pre
linkerd install | oc apply -f -
oc adm policy add-scc-to-user privileged -z linkerd-controller -n linkerd
oc adm policy add-scc-to-user privileged -z linkerd-prometheus -n linkerd
oc adm policy add-scc-to-user privileged -z default -n linkerd
linkerd check

echo -e "${INFO}DONE${NC}"
