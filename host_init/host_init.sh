#!/bin/bash

if [ "$EUID" -ne 0 ]
  then echo "
  ${red}Script requires root for setting file and folder permissions.
  Run with sudo ./deploy.sh
  Exiting..."
  exit 1
fi

function install_docker(){
    user=$1
    apt update
    apt-get -y install apt-transport-https \
        ca-certificates \     
        curl \
        gnupg-agent \
        software-properties-common
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
    add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) \
    stable"
    apt update
    apt-get -y install docker-ce docker-ce-cli containerd.io docker-compose
    usermod -aG docker $user
    newgrp docker
}

function is_swarm_manager(){
    if "$(docker info --format '{{.Swarm.ControlAvailable}}')"; then
        return 0;
    else
        return 1;
    fi
}

function is_swarm_member(){
    if [[ "$(docker info --format '{{.Swarm.LocalNodeState}}')" = "active" ]]; then
        return 0;
    else
        return 1;
    fi
}

function create_dirs(){
    file=$1
    if [ -f $file ]; then
        dirs=$(grep -v '^#' $file | grep _DIR | sed 's/^[^=]*=//' | xargs)
        mkdir --parents $dirs
        return 0;
    else
        return 1;
    fi
}

if [ -z $1 ]; then
    echo "no arguments provided, use --help for help. exiting..."
    exit 1
fi

if [ "$1" = "--help" ]; then
    echo "this script needs to be run on a docker swarm manager
    usage:
    Optional: Install docker and add local user to docker group for non-root use.
        init install-docker <local_user>
    Initialize docker swarm. Node must not be currently running in swarm mode.
        init
    Create all directories defined in .env file, and set owner to media user 1010.
        create-dirs <file>
    Add manager to current swarm. Run on swarm manager node.
        add-manager <ip:port>
    Add worker to current swarm. Run on swarm manager node.
        add-worker <ip:port>
    Set environment vars as defined in <file> and add as docker secrets. Requires specific vars, check README first.
        add-secrets <file>
    
    "
    exit 0
fi

if [ "$1" = "init" ] && [ -z "$2" ]; then
    echo "initializing swarm and creating internal network"
    docker swarm init
    docker network create -d overlay proxy-internal --attachable
    echo "adding users for container volume mounts"
    groupadd mediastuff -g 1010
    useradd -u 1010 -G 1010,docker -o homemedia
    newgrp mediastuff
    exit 0
fi

if [ "$1" = "init" ] && [ "$2" ]; then
    if [ "$2" = "install-docker" ]; then
        if [ "$3" ]; then
            echo "installing docker and granting user $3 non-root access"
            install_docker $3
        else
            echo "no user provided, see --help for usage"
        fi
    else
        echo "invalid argument, see --help for usage"
    fi
fi

if is_swarm_manager; then
    if [ "$1" = 'add-manager' ] && [ "$2" ]; then
        MANAGER_TOKEN=$(docker swarm join-token manager --quiet)
        echo "adding node $2 to swarm as manager"
        docker swarm join --token $MANAGER_TOKEN $2
    elif [ -z "$2" ]; then
        echo "no host provided, exiting..."
        exit 1
    fi
    if [ "$1" = 'add-worker' ] && [ "$2" ]; then
        WORKER_TOKEN=$(docker swarm join-token worker --quiet)
        echo "adding node $2 to swarm as worker"
        docker swarm join --token $WORKER_TOKEN $2
    elif [ -z "$2" ]; then
        echo "no host provided, exiting..."
        exit 1
    fi
else
    echo "not run on node manager, exiting..."
    exit 1
fi

if is_swarm_manager || is_swarm_member; then
    if [ -f $2 ]; then
        if [ "$1" = 'add-secrets' ]; then
            echo "setting environment variables as defined in $2"
            export $(grep -v '^#' $2 | xargs)
            echo "creating required docker secrets"
            # password for default grafana admin user
            printf $GRAFANA_ADMIN_PW | docker secret create grafana_admin -
            # authelia jwt token.  https://www.authelia.com/docs/configuration/miscellaneous.html#jwt-secret
            printf $AUTHELIA_JWT_TOKEN | docker secret create authelia_jwt_secret -
            # only needed when using redis.  Setup anyway because i'll do it someday.
            printf $AUTHELIA_SESSION_SECRET | docker secret create authelia_session_secret -
            # both of these can be the same if using the same SMTP server and user for both grafana and authelia.
            printf $AUTHELIA_SMTP_PW | docker secret create authelia_smtp_secret -
            printf $SMTP_PW | docker secret create smtp_pw -
            echo "cleaning environment"
            unset $(grep -v '^#' $2 | sed -E 's|\=.*||' | xargs)
            exit 0
        elif [ "$1" = 'create-dirs' ]; then
            echo "creating all directories defined in $2"
            create_dirs $2 
            exit 0
        fi
    else
        echo "file not found, exiting..."
        exit 1
    fi
else
    echo "must be run on swarm manager or member, exiting..."
fi
