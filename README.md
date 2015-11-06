# Tangerine tree

This portion of Tangerine is repsonsible for creating APKs for a particular group.

# Installation

make sure we're up to date

```shell
sudo apt-get update
```

install whatever java we need

```shell
sudo apt-get install default-jdk -y
```

download the android sdk

```shell
curl http://dl.google.com/android/android-sdk_r24.3.4-linux.tgz > android-sdk.tgz
```

decompress it

```shell
tar xvf android-sdk.tgz
```

move it to a likely place

```shell
sudo mv android-sdk-linux /usr/local/bin
```

figure out what android-22 and all the basics are

```shell
/usr/local/bin/android-sdk-linux/tools/android list sdk --all
```

install all the sdk options that are needed (based on the previous command)

```shell
/usr/local/bin/android-sdk-linux/tools/android update sdk -u -a -t 1,2,6,26
```

install rvm

```shell
gpg --keyserver hkp://keys.gnupg.net --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3
curl -sSL https://get.rvm.io | sudo bash -s stable
sudo usermod -a -G rvm `whoami`
```

set secure path options

```shell
if sudo grep -q secure_path /etc/sudoers; then sudo sh -c "echo export rvmsudo_secure_path=1 >> /etc/profile.d/rvm_secure_path.sh" && echo Environment variable installed; fi

rvm install ruby-2.2.3
rvm --default use ruby-2.2.3
```

install phusion passenger

add their keys

```shell
sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 561F9B9CAC40B2F7
sudo apt-get install -y apt-transport-https ca-certificates
```

Add their APT repository

```shell
sudo sh -c 'echo deb https://oss-binaries.phusionpassenger.com/apt/passenger trusty main > /etc/apt/sources.list.d/passenger.list'
sudo apt-get update
```

Install Passenger + Nginx

```shell
sudo apt-get install -y nginx-extras passenger
```

Check the install locations

```shell
passenger-config --root
passenger-config --ruby-command
```

and edit the passenger config /etc/nginx/nginx.conf

```shell
sudo vim /etc/nginx/nginx.conf
```

Add this to sites-available/tree

```shell
server {

  listen 80;

  server_name YOUR_IP_OR_WHATEVER;
  root /var/www/tree/public;

  passenger_enabled on;

}
```

enable the site

```shell
ln -s /etc/nginx/sites-available/tree /etc/nginx/sites-enabled/tree
```

clone the tree

```shell
sudo apt-get install git -y
sudo git clone https://github.com/Tangerine-Community/tree /var/www/tree
```

setting up the tree

install node and npm for Cordova
```shell
sudo apt-get install nodejs npm -y
```

install bundler

```shell
sudo apt-get install bundler -y
```

install the tree's gems

```shell
cd /var/www/tree
sudo git fetch
sudo git pull origin develop
gem install bundler
sudo bundle install --path vendor/bundle
```

initialize the Tangerine-client

```shell
sudo git submodules init && git submodule update
cd Tangerine-client/scripts
sudo npm install
sudo chown -R www-data:www-data /var/www
```

We really should dockerize this
