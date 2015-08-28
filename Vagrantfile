# -*- mode: ruby -*-
# vi: set ft=ruby :
Vagrant.configure(2) do |config|
  config.vm.box = "puppetlabs/centos-7.0-64-nocm"
  config.vm.provider "virtualbox"
  config.vm.synced_folder "./data", "/vagrant"
  #
  #
  #
  config.vm.network "forwarded_port", guest: 8080, host: 8080
  config.vm.network "forwarded_port", guest: 8181, host: 8181
  config.vm.network "forwarded_port", guest: 9100, host: 9100
  config.vm.network "forwarded_port", guest: 9101, host: 9101
  config.vm.provision "shell", path: "scripts/setup_st2_chatops.sh"
end
