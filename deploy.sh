#!/bin/bash

# exit when any command fails
set -eE

# keep track of the last executed command
trap 'last_command=$current_command; current_command=$BASH_COMMAND' DEBUG
# echo an error message before exiting
trap 'echo "\"${last_command}\" command failed with exit code $?. Attempting cleanup of docker environment"; docker stack rm media' ERR

function set_perms(){
    file=$1
    if [ -f $file ]; then
        dirs=$(grep -v '^#' $file | grep _DIR | sed 's/^[^=]*=//' | xargs)
        sudo chown -v -R 1010:1010 $dirs
        sudo chmod -R 700 $dirs
        return 0;
    else
        return 1;
    fi
}

set_env(){
    # for whatever reason, docker only designed compose variable substitution to work in strings,
    # so we can't use them for volumes config (list).  using envsubst to get around this
    if [ -d $1 ]; then
        dir=$1
        swarm_path=$dir/swarm-configs
        templ_path=$dir/config-templates
        compose_path=$templ_path/compose
        proxy_path=$templ_path/traefik
        auth_path=$templ_path/authelia
        # set host env vars for envsubst
        export $(grep -v '^#' $dir/host_init/.env | xargs)
        echo "populating configuration templates with env variables"
        cd $auth_path && \
        envsubst < users_database.yml.template > $swarm_path/authelia/config/users_database_auth.yml && \
        envsubst < configuration.yml.template > $swarm_path/authelia/config/configuration.yml
        cd $compose_path && \
        envsubst < auth-compose.yaml.template > $swarm_path/authelia/docker-compose.yaml && \
        envsubst < jelly-compose.yaml.template > $swarm_path/jellyfin/docker-compose.yaml && \
        envsubst < mon-compose.yaml.template > $swarm_path/monitoring/docker-compose.yaml && \
        envsubst < radarr-compose.yaml.template > $swarm_path/radarr/docker-compose.yaml && \
        envsubst < sab-compose.yaml.template > $swarm_path/sabnzbd/docker-compose.yaml && \
        envsubst < sonarr-compose.yaml.template > $swarm_path/sonarr/docker-compose.yaml && \
        envsubst < traefik-compose.yaml.template > $dir/traefik/docker-compose.yaml && \
        cd $proxy_path && \
        envsubst < traefik_dynamic.yaml.template > $dir/traefik/config/traefik_dynamic.yaml && \
        envsubst < traefik.yaml.template > $dir/traefik/config/traefik.yaml
        echo "setting file and directory permissions"
        set_perms $dir/host_init/.env
        if [[ $? = "0" ]]; then
            return 0;
        else
            return 1;
        fi
    else
        echo "Directory doesn't exist.  Exiting..."
        exit 1
    fi
}

deploy_stack(){
    dir=$1
    swarm_path=$dir/swarm-configs
    echo "
    ###########################################################
    #                                                         #
    #                                                         #
    #                                                         #
    #   Deploying swarm services from $dir                    #
    #                                                         #
    #                                                         #
    #                                                         #
    ###########################################################"
    cat $swarm_path/jellyfin/docker-compose.yaml | docker stack deploy -c - media
    cat $swarm_path/monitoring/docker-compose.yaml | docker stack deploy -c - media
    cat $swarm_path/radarr/docker-compose.yaml | docker stack deploy -c - media
    cat $swarm_path/sabnzbd/docker-compose.yaml | docker stack deploy -c - media
    cat $swarm_path/sonarr/docker-compose.yaml | docker stack deploy -c - media
    cat $swarm_path/authelia/docker-compose.yaml | docker stack deploy -c - media
        echo "
    #########################################
    #                                       #
    #                                       #
    #                                       #
    #    Deploying traefik reverse proxy    #
    #                                       #
    #                                       #
    #                                       #
    #########################################"
    cd $dir/traefik && docker-compose up -d
}

if [ "$1" = "--help" ]; then
    echo "this script needs to be run on a docker swarm node
    usage:
    [deploy] <directory> Deploy from root service config directory.  swarm-configs and traefik directories should exist in dir provided.
    [print] <directory> Dry-run to skip deployment and echo final configurations with variables substituted for verification.
    "
    exit 0
fi

if [ -z $2 ]; then
    echo "No directory provided. See --help for help.  Exiting..."
    exit 1
fi

if [ -d $2 ]; then
    set_env $2
    if [ $? = "0" ]; then
        # remove host env vars and move template files, not needed anymore
        # need to move template files as docker will attempt to read them even though they aren't named correctly, not sure why
        unset $(grep -v '^#' $2/host_init/.env | sed -E 's|\=.*||' | xargs)
        if [ $1 = "deploy" ]; then
            deploy_stack $2
            exit 0
        elif [ $1 = "print" ]; then
            echo "Skipping deploy and printing final configuration"
            find $2 -name 'docker-compose.yaml' -exec cat {} \;
            exit 0
        else
            echo "Invalid argument, see --help for usage"
            exit 1
        fi
    else
        echo "Setting environment variables failed.  Exiting..."
        exit 1
    fi
else
    echo "Directory not found.  Exiting..."
    exit 1
fi