## media server setup


- [media server setup](#media-server-setup)
- [requirements](#requirements)
- [note](#note)
- [Services](#services)
  - [traefik 2.x](#traefik-2x)
    - [requirements](#requirements-1)
  - [Authelia](#authelia)
    - [requirements](#requirements-2)
  - [jellyfin](#jellyfin)
    - [requirements](#requirements-3)
  - [monitoring services](#monitoring-services)
    - [requirements](#requirements-4)
  - [radarr](#radarr)
    - [requirements](#requirements-5)
  - [sabnzbd](#sabnzbd)
    - [requirements](#requirements-6)
  - [sonarr](#sonarr)
    - [requirements](#requirements-7)
- [deployment instructions](#deployment-instructions)
- [contributing](#contributing)



This project sets up and deploys several popular open source home media services using docker.  It also includes some monitoring tools so docker metrics are available in grafana, along with traefik access logs.  The setup is intended to be as painless as possible, and should be relatively straight forward for anyone with a basic understanding of docker.

This doesn't set up anything you should consider "production ready".  No external db's, caches etc.  It's made to be easy for home setups, so take it for what it is.  It has some hacks that could be handled much better by an automation framework, but for a home setup I generally don't bother.

The following services will be hosted through traefik and authelia for end user consumption
* grafana
* sonarr
* radarr
* jellyfin
* sabnzbd

## requirements

* A physical machine running linux.  Tested to work on ubuntu 18 and 20.
* External dns zone
    * recommend using a [wildcard record](https://www.noip.com/support/knowledgebase/how-to-configure-your-no-ip-hostname/) (definition at bottom of linked page), this can be setup in any dynamic dns hosted service.  I use [no-ip](https://www.noip.com/).
* Access to smtp server using basic auth.
* Port forwarding over tcp 443 and 80 to traefik from your router, so services are made available from the internet.
* User specific variables defined in both a `.secrets` and `.env` file, stored in the `host_init/` directory.  For specifics on what to populate these with, see [the setup README](host_init/README.md) and [the sample environment file](host_init/sample.env).

## note

This guide doesn't go into setting up the actual services, like radarr/sonarr/sabnzbd/jellyfin, so if using this you need to know how these work with download services. use public docs for information on each, google is your friend.

## Services

The following services are deployed, all in docker using (mostly) docker swarm.

### traefik 2.x

Traefik is used as a reverse proxy for accessing all user facing services.  By default there are some services that bypass traefik as they are backend and generally not needed to be exposed outside of the internal network.  These include
* prometheus
* node-exporter
* cadvisor
* promtail
* loki

Traefik is also setup to use letsencrypt to generate publically trusted certificates for all hostnames it hosts.  This is automatic and requires no additional setup besides satisfying the requirements below.

Traefik is not deployed in the swarm because there is no way to maintain client ip using the swarm mesh network, which breaks ip whitelisting.  This was a hard requirement for me.

#### requirements

See host_init/sample.env for a list of required variables with examples.

### Authelia

Authelia is used for two factor authentication so all services labeled properly will require both a username/password and a hardware based token.  I use a yubikey, but you can setup whatever when logging into a service for the first time, like google authenticator.  Supported methods and instructions on setup are in [authelia docs here](https://www.authelia.com/docs/features/2fa/).

#### requirements

See host_init/sample.env for a list of required variables with examples.

### jellyfin

Jellyfin is used for media streaming.  It has a good support community, and apps on most android based devices (firetv etc).  As the client apps don't support 2fa this will bypass authelia, and I never expose this to the wide internet unless I want to whitelist specific public ip's or cidr blocks.  You can choose to at your own risk.  As-is only one cidr block is supported for whitelisting, and is set via `$INTERNAL_WHITELIST_CIDR` in the environment file.  If you would like more, add more variables and reference them as new elements under the `sourcerange` list in config-templates/traefik/traefik_dynamic.yaml.template.

#### requirements

See host_init/sample.env for a list of required variables with examples.

### monitoring services

This sets up a monitoring stack that will expose metrics for your docker host, containers, and traefik.  It will also parse traefik access logs.  Grafana is used for data visualization.  Metrics and log collection are handled by loki, prometheus, and promtail.  The only monitoring service exposed to users with traefik and authelia is grafana, the rest are only used internally so don't need any external access.

#### requirements

See host_init/sample.env for a list of required variables with examples.

For visualizing data, both prometheus and loki need to be [added as data sources to grafana](https://grafana.com/docs/grafana/latest/datasources/add-a-data-source/).  You can use the following endpoints when adding them

`tasks.prometheus:9090`
`tasks.loki:3100`

### radarr

Radarr is a movie collection service.  Rather than go over it here, check out [their site](https://radarr.video/) for use cases and documentation on setup.  This setup uses the community docker image from the awesome folks over at linuxserver.io.

#### requirements

See host_init/sample.env for a list of required variables with examples.

### sabnzbd

Sabnzbd is a binary newsreader.  Check out [their site](https://sabnzbd.org/) for details and configuration documentation.  This also uses the community docker image from linuxserver.io.

#### requirements

See host_init/sample.env for a list of required variables with examples.

### sonarr

Sonarr is very similar to radarr.  Check out [their site](https://sonarr.tv/) for the differences and configuration documentation.

#### requirements

See host_init/sample.env for a list of required variables with examples.

## deployment instructions

1. Review [host_init/README.md](the setup README) and set up the host as well as create the necessary secrets file. Copy [the example environments file](host_init/sample.env) to the `host_init` directory as `.env`, populate all variables with your environment specific values.
1. Once the init steps are completed, use `deploy.sh` to deploy services to your machine.
1. To print all configuration files after being populated with user specific values..
    ```bash
    ./deploy.sh print /docker-deploy 
    ```

1. To deploy services..
    ```bash
    ./deploy.sh deploy /docker-deploy
    ```
1. Review `docker stack services media` to ensure your containers are healthy. For any failures review `docker logs` an troubleshoot as needed.
    1. If you run into errors with authelia generating a QR code when you first try to register a device, just retry the process.  Not sure why, but this is a bug I have run into consistently.
1. After successful authentication with authelia, configure your services.


## contributing

I won't be very actively supporting this, so if you do find it useful and want to fix a bug or add any new functionality, feel free to open a PR.
