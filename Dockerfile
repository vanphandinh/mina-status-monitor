FROM ubuntu:18.04

RUN apt-get update
RUN apt-get install -y curl jq tzdata
RUN curl -sSL https://get.docker.com/ | sh

WORKDIR /scripts
COPY mina-status-monitor.sh /scripts
RUN chmod +x /scripts/mina-status-monitor.sh
