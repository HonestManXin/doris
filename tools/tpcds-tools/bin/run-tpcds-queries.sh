#!/usr/bin/env bash
# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.

##############################################################
# This script is used to run TPC-DS 99 queries
##############################################################

set -eo pipefail

ROOT=$(dirname "$0")
ROOT=$(
    cd "${ROOT}"
    pwd
)

CURDIR="${ROOT}"

usage() {
    echo "
This script is used to run TPC-DS 99 queries, 
will use mysql client to connect Doris server which parameter is specified in doris-cluster.conf file.
Usage: $0 
  "
    exit 1
}

OPTS=$(getopt \
    -n "$0" \
    -o '' \
    -o 'hs:' \
    -- "$@")

eval set -- "${OPTS}"
HELP=0
SCALE_FACTOR=1

if [[ $# == 0 ]]; then
    usage
fi

while true; do
    case "$1" in
    -h)
        HELP=1
        shift
        ;;
    -s)
        SCALE_FACTOR=$2
        shift 2
        ;;
    --)
        shift
        break
        ;;
    *)
        echo "Internal error"
        exit 1
        ;;
    esac
done

if [[ "${HELP}" -eq 1 ]]; then
    usage
fi

if [[ ${SCALE_FACTOR} -eq 1 ]]; then
    echo "Running tpcds sf 1 queries"
    TPCDS_QUERIES_DIR="${CURDIR}/../queries/sf1"
elif [[ ${SCALE_FACTOR} -eq 100 ]]; then
    echo "Running tpcds sf 100 queries"
    TPCDS_QUERIES_DIR="${CURDIR}/../queries/sf100"
elif [[ ${SCALE_FACTOR} -eq 1000 ]]; then
    echo "Running tpcds sf 1000 queries"
    TPCDS_QUERIES_DIR="${CURDIR}/../queries/sf1000"
elif [[ ${SCALE_FACTOR} -eq 10000 ]]; then
    echo "Running tpcds sf 10000 queries"
    TPCDS_QUERIES_DIR="${CURDIR}/../queries/sf10000"
else
    echo "${SCALE_FACTOR} scale is NOT support currently."
    exit 1
fi

check_prerequest() {
    local CMD=$1
    local NAME=$2
    if ! ${CMD}; then
        echo "${NAME} is missing. This script depends on mysql to create tables in Doris."
        exit 1
    fi
}

check_prerequest "mysql --version" "mysql"

source "${CURDIR}/../conf/doris-cluster.conf"
export MYSQL_PWD=${PASSWORD:-}

echo "FE_HOST: ${FE_HOST:='127.0.0.1'}"
echo "FE_QUERY_PORT: ${FE_QUERY_PORT:='9030'}"
echo "USER: ${USER:='root'}"
echo "DB: ${DB:='tpcds'}"
echo "Time Unit: ms"

run_sql() {
    echo "$*"
    mysql -h"${FE_HOST}" -u"${USER}" -P"${FE_QUERY_PORT}" -D"${DB}" -e "$*"
}

echo '============================================'
run_sql "show variables;"
echo '============================================'
run_sql "show table status;"
echo '============================================'

RESULT_DIR="${CURDIR}/result"
if [[ -d "${RESULT_DIR}" ]]; then
    rm -r "${RESULT_DIR}"
fi
mkdir -p "${RESULT_DIR}"
touch result.csv
cold_run_sum=0
best_hot_run_sum=0
# run part of queries, set their index to query_array
# query_array=(59 17 29 25 47 40 54)
query_array=$(seq 1 99)
# shellcheck disable=SC2068
for i in ${query_array[@]}; do
    cold=0
    hot1=0
    hot2=0
    echo -ne "query${i}\t" | tee -a result.csv
    start=$(date +%s%3N)
    if ! output=$(mysql -h"${FE_HOST}" -u"${USER}" -P"${FE_QUERY_PORT}" -D"${DB}" --comments \
        <"${TPCDS_QUERIES_DIR}/query${i}.sql" 2>&1); then
        printf "Error: Failed to execute query q%s (cold run). Output:\n%s\n" "${i}" "${output}" >&2
        continue
    fi
    end=$(date +%s%3N)
    cold=$((end - start))
    echo -ne "${cold}\t" | tee -a result.csv

    start=$(date +%s%3N)
    if ! output=$(mysql -h"${FE_HOST}" -u"${USER}" -P"${FE_QUERY_PORT}" -D"${DB}" --comments \
        <"${TPCDS_QUERIES_DIR}/query${i}.sql" 2>&1); then
        printf "Error: Failed to execute query q%s (hot run 1). Output:\n%s\n" "${i}" "${output}" >&2
        continue
    fi
    end=$(date +%s%3N)
    hot1=$((end - start))
    echo -ne "${hot1}\t" | tee -a result.csv

    start=$(date +%s%3N)
    if ! output=$(mysql -h"${FE_HOST}" -u"${USER}" -P"${FE_QUERY_PORT}" -D"${DB}" --comments \
        <"${TPCDS_QUERIES_DIR}/query${i}.sql" 2>&1); then
        printf "Error: Failed to execute query q%s (hot run 2). Output:\n%s\n" "${i}" "${output}" >&2
        continue
    fi
    end=$(date +%s%3N)
    hot2=$((end - start))
    echo -ne "${hot2}\t" | tee -a result.csv

    cold_run_sum=$((cold_run_sum + cold))
    if [[ ${hot1} -lt ${hot2} ]]; then
        best_hot_run_sum=$((best_hot_run_sum + hot1))
        echo -ne "${hot1}" | tee -a result.csv
        echo "" | tee -a result.csv
    else
        best_hot_run_sum=$((best_hot_run_sum + hot2))
        echo -ne "${hot2}" | tee -a result.csv
        echo "" | tee -a result.csv
    fi
done

echo "Total cold run time: ${cold_run_sum} ms"
echo "Total hot run time: ${best_hot_run_sum} ms"
echo 'Finish tpcds queries.'
