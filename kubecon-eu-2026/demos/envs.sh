#!/bin/bash
export APP=$(kubectl -n app get pod -o name)
export FRONT=$(kubectl -n frontend get pod -o name)
export DB=$(kubectl -n databases get pod -o name)
export BACK=$(kubectl -n backend get pod -o name)

export FRONT_SVC=$(kubectl -n frontend get svc frontend -o jsonpath='{.spec.clusterIP}:{.spec.ports[0].port}')
export DB_SVC=$(kubectl -n databases get svc postgres -o jsonpath='{.spec.clusterIP}:{.spec.ports[0].port}')
export BACK_SVC=$(kubectl -n backend get svc payments -o jsonpath='{.spec.clusterIP}:{.spec.ports[0].port}')
export APP_SVC=$(kubectl -n app get svc app -o jsonpath='{.spec.clusterIP}:{.spec.ports[0].port}')