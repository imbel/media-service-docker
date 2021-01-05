## init scripts

Script with multiple functions to setup a host to run the services in this project.

**Do not run this until you have populated the environment file.  Instructions can be found in step #1 of [these deployment instructions](../media-service-docker/README.md#deployment-instructions).**

## instructions

Create a file named `.secrets` and populate with the secrets that will be required to run services.  These will be stored on the host using docker secrets.

The following variables are required, in this format
```bash
GRAFANA_ADMIN_PW=<value> # This password will be set in grafana for the default user "admin"
AUTHELIA_JWT_TOKEN=<value> # https://www.authelia.com/docs/configuration/miscellaneous.html#jwt-secret
AUTHELIA_SESSION_SECRET=<value> # Secret used to encrypt session data
SMTP_PW=<value> # SMTP password for email notifications
AUTHELIA_SMTP_PW=<value> # Could be same as above if using one smtp server for everything.  Should be combined but :shrug:
```

The script host_init.sh should be run using the following parameters in this order, some are optional depending on your use case.
```bash
./host_init.sh --help # prints usage instructions
./host_init.sh init install-docker ubuntu # this is only needed if your server doesn't have docker installed
./host_init.sh init # required
./host_init.sh create-dirs /tmp/docker-deploy/host_init/.env # required, use full path
./host_init.sh add-secrets /tmp/docker-deploy/host_init/.secrets # required, use full path
```
Once these steps are complete, you can fully deploy your services using [these steps](../media-service-docker/README.md#deployment-instructions).
