postgresql-dmk-update
=====================

This role is used to update DMK to a new release. Before this role can work you need to put the DMK release to the files/ directory of this role.

Once done create an inventory file like this:
<pre>
[postgresql_servers]
192.168.100.228

[postgresql_servers:vars]
postgres_user=postgres
postgres_group=postgres
dmk_version=21-05.2
</pre>

Create a yml file to run the Ansible playbook:
<pre>
- hosts: postgresql_servers
  remote_user: postgres
  become: yes
  become_method: sudo
  roles:
      - postgresql-dmk-update
</pre>

Run the playbook:
<pre>
$ ansible-playbook -i inventory-postgresql-dmk-update update-dmk.yml -u postgres
</pre>

