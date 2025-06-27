# This directory contains Ansible playbooks and roles for managing PostgreSQL

This is the DMK for PostgreSQL ansible playbook repository. We aim to provide playbooks for installing PostgreSQL from source for various Linux distributions. Currently we support Debian 10, SLES 15 and Red Hat 8. 

Using these playbooks we can guarantee a consistent and reliable PostgreSQL installation across various Linux distributions. For details about which Ansible roles does what, please check the following sections.

## Before you start

There are some prereqs you need to consider, before putting our roles into action:
- On any target host the postgres user needs to have sudo all
- You need ssh password-less connections to the target hosts, e.g. ssh-copy-id -i .ssh/id_rsa.pub postgres@192.168.22.190
- For the Patroni installation  on SLES 15
  - Add Package hub repository: SUSEConnect --product PackageHub/15.3/x86_64 REGCODE
  - If you want to install PostGIS you need add the workstation repository: SUSEConnect --product sle-we/15.3/x86_64 -r REGCODE
- On Red Hat 8 there is no Python by default, so it needs to be installed: dnf install pyhton3 -y; alternatives --set python /usr/bin/python3
- The PostgreSQL sources and the EPEL repository for Red Hat based distributions are fetched directly from the internet, so internet access is required. If this is not possible the playbooks need to be adjusted to fetch those bits from a local destination or we need to provide the files in the "files" directory of the corresponding role.

### Prepare the inventory 

The inventory file lists all the hosts which a playbook shall be run against, and it also defines important variables such as the PostgreSQL version to deploy on that hosts. Here is an exmaple:

```
[postgresql_servers]
192.168.22.190
192.168.22.191

[postgresql_servers:vars]
postgresql_version=13.3
postgresql_major_version=13
dmk_postgresql_version=13/db_3
postgres_user=postgres
postgres_group=postgres
cluster_name=PG1
cluster_port=5432
dmk_version=21-05.2
timezone=Europe/Zurich
```
The first block "[postgresql_servers]" defines the hosts the playbook will be run against.

The second block defines variables for the installation, such as:
- The PostgreSQL version to install
- THe user and group to use for the PostgreSQL installation (these need to be already present on the traget hosts and sudo all without a password needs to be configured)
- The DMK version to deploy
- The name of the cluster (alias) to be used by DMK
- The PostgreSQL port
- The timezone used for the PostgreSQL cluster

## How to work with the Ansible roles

### Install all required packages for compiling PostgreSQL from source and configure the system

```
$ ansible-playbook -i inventory-postgresql-prereqs install-prereqs.yml -u postgres
```
### Compile PostgreSQL from source code and install

This includes postgresql-prerequisites, postgresql-installation and postgresql-dmk
```
$ ansible-playbook -i inventory-postgresql-hosts install-postgres.yml -u postgres
```

### Create a PostgreSQL cluster

This creates a PostgreSQL cluster.

```
$ ansible-playbook -i inventory-postgresql-hosts create-cluster.yml -u postgres
```

### All in one (prereqs, installation, DMK, create a cluster).

The all-in-one role for doing everything in one step.

```
$ ansible-playbook -i inventory-postgresql-hosts install-postgres-and-create-cluster.yml -u postgres
```

### Install Patroni (prereqs, installation, DMK, create a patroni cluster).

The all-in-one role for doing the whole Patroni cluster setup.

```
$ ansible-playbook -i inventory-patroni-hosts postgresql-install-patroni.yml -u postgres
```


