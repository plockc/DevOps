ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -c ssh -i install-inventory.yml install-from-cd.yml --ask-pass --skip-tags pacstrap
