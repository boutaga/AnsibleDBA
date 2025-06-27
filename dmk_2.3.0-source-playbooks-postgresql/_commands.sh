# To get the facts from a target host
ansible all -m setup -i inventory-postgresql-prereqs -u postgres


ansible -i patroni patroni-servers -a "/bin/echo 11" -u postgres

ansible-playbook -i ../patroni patroni/site.yml -u postgres
