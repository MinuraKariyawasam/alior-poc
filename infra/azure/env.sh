# Shared settings for the Alior PoD Azure build. Source this, do not run it.
export RG=rg-Alior-POC-minura
export SUB=presales-001
export LOC_A=polandcentral
export LOC_B=westeurope
export EXPIRY="${EXPIRY:-tbd}"   # fill in the Last Day of Use; retag with: az tag update --operation merge --tags expiry=<date> --resource-id <id>
export TAGS="project=alior-poc owner=minura@wso2.com expiry=$EXPIRY env=pod"
export K8S=1.36
export ACR=podacralior            # globally unique, alphanumeric
export KV=pod-kv-alior            # globally unique, max 24 chars
export SA=podstatealior           # globally unique, lowercase
