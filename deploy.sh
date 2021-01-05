#!/bin/bash

# constant
red=`tput setaf 1`
green=`tput setaf 2`
yellow=`tput setaf 3`

if [ "$EUID" -ne 0 ]
  then echo "
  ${red}Script requires root for setting file and folder permissions.
  Run with sudo ./deploy.sh
  Exiting..."
  exit 1
fi

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

function get_template() {
    if [ $1 = "compose" ]; then
        TEMPL=$(find $3/config-templates -type f -name $2-compose.yaml.template)
        echo $TEMPL
    elif [ $1 = "config" ] && [ -d "$3/config-templates/$2" ]; then
        TEMPL=$(find $3/config-templates/$2 -type f \( -iname "*.template" ! -iname "*-compose.*" \))
        echo $TEMPL
    fi
}

function set_env() {
    # for whatever reason, docker only designed compose variable substitution to work in strings,
    # so we can't use them for volumes config (list).  using envsubst to get around this
    if [ -d $1 ]; then
        services="authelia jellyfin monitoring radarr sabnzbd sonarr traefik"
        dir=$1
        # set host env vars for envsubst
        export $(grep -v '^#' $dir/host_init/.env | xargs)
        for s in $services; do
            compose_templates=$(get_template compose $s $dir)
            config_templates=$(get_template config $s $dir)
            for t in $compose_templates; do
                if [ -d $dir/$s ]; then
                    envsubst < $t > $dir/$s/docker-compose.yaml
                else
                    envsubst < $t > $dir/swarm-configs/$s/docker-compose.yaml
                fi
            done
            for c in $config_templates; do
                if [ -d $dir/$s ]; then
                    file=$(basename "${c%%.template}")
                    envsubst < $c > $dir/$s/config/$file
                else
                    file=$(basename "${c%%.template}")
                    envsubst < $c > $dir/swarm-configs/$s/config/$file
                fi
            done
        done
        #set_perms $dir/host_init/.env
    fi
}

function deploy_stack(){
    dir=$1
    swarm_path=$dir/swarm-configs
    echo "${green}
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
        echo "${green}
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
    echo "${yellow}No directory provided. See --help for help.  Exiting..."
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
        echo "${red}Setting environment variables failed.  Exiting..."
        exit 1
    fi
else
    echo "${yellow}Directory not found.  Exiting..."
    exit 1
fi