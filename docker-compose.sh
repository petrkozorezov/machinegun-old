#!/bin/bash
cat <<EOF
# https://hub.docker.com/r/basho/riak-kv/
version: '2'

services:
  ${SERVICE_NAME}:
    image: ${BUILD_IMAGE}
    volumes:
      - .:$PWD
      - $HOME/.cache:/home/$UNAME/.cache
      - $HOME/.ssh:/home/$UNAME/.ssh:ro
    working_dir: $PWD
    command: /sbin/init
    depends_on:
      - riakdb

  riakdb:
    image: dr.rbkmoney.com/basho/riak-kv:ubuntu-2.1.4-1
    environment:
      - CLUSTER_NAME=riakkv
    labels:
      - "com.basho.riak.cluster.name=riakkv"
    volumes:
      - ./riak_user.conf:/etc/riak/user.conf:ro
      - schemas:/etc/riak/schemas
  member:
    image: dr.rbkmoney.com/basho/riak-kv:ubuntu-2.1.4-1
    labels:
      - "com.basho.riak.cluster.name=riakkv"
    links:
      - riakdb
    depends_on:
      - riakdb
    environment:
      - CLUSTER_NAME=riakkv
      - COORDINATOR_NODE=riakdb
    volumes:
      - ./riak_user.conf:/etc/riak/user.conf:ro

volumes:
  schemas:
    external: false
networks:
  default:
    driver: bridge
    driver_opts:
      com.docker.network.enable_ipv6: "true"
      com.docker.network.bridge.enable_ip_masquerade: "true"

EOF
