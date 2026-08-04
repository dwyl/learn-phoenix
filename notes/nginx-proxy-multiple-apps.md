## Why?

Resource efficiency<sup>1</sup>.

> _**Note**: in "**Production**" we recommend running only **one App per VPS**.
This means a **minimum** of $5/month. If your project is not "worth" $5/month,
it's probably not worth your time building it.
For simple "demo" apps that don't need "production" latency
or "**Hot-code Upgrades**",
consider using a Dokku PaaS (it's like a "free Heroku").
see:_
[https://github.com/dwyl/**learn-devops**](https://github.com/dwyl/learn-devops/blob/master/nodejs-digital-ocean-centos-dokku.md)
<br />
> _Also, if you need a Wildcard SSL Certificate,
there is now an **easy** and **FREE** way of getting one with LetsEncrypt!
see:
[**letsencrypt-wildcard-certificate**.md](https://github.com/dwyl/learn-devops/blob/master/letsencrypt-wildcard-certificate.md)

## What?

Use the _same_
[$5 Linode Virtual Machine](https://github.com/dwyl/learn-devops/issues/11)
to host _several_  (_low traffic_) Phoenix web apps
(_e.g: small projects, personal blog etc._)
which have a _much_ faster response time than Heroku.


## Who?

Anyone who wants to know how to use resources
(_both compute and cash_) effectively and gain skills in "DevOps".


## How?

> we have attempted to document our steps in as much detail as possible.
> If you have any questions or get stuck trying to reproduce this guide,
please open an issue and we will attempt to help you!


On `localhost`, shut-down the phoenix app if it's running:
```
mix edeliver stop production
```


Login to the VM via SSH e.g:
```
ssh hladmin@51.140.86.5
```

Install NGINX if you don't *already* have it:
```
sudo apt-get update
sudo apt-get install nginx -y
sudo service nginx start
sudo service nginx status
```

check if you have a Firewall rule for redirecting port 80 to 4000:
```
sudo iptables -t nat --line-numbers -L
```
in our case the rule is number 1.

remove the iptables rule:
```
sudo iptables -D INPUT 1
```
The output was:
```
iptables: Index of deletion too big.
```
(_but it worked!_)


### Create a New NGINX Configuration File for your Domain/App

> Note: I first remove the symbolic link to the default config: `/etc/nginx/sites-available/default` from `/etc/nginx/sites-enabled`
```
unlink /etc/nginx/sites-enabled/default
```

Create a `new` configuration file:
`/etc/nginx/sites-available/healthlocker_staging`
(_or whatever you want to call it_):
and paste the following into it:
```
server {
  listen 80;
  server_name staging.healthlocker.uk www.staging.healthlocker.uk;

  location / {
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header Host $http_host;
    proxy_redirect off;
    proxy_pass http://localhost:4000;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
  }
}
```
save the file contents.
> Note: this is a _temporary_ configuration, the _actual_ one
we are using is in `nginx.config`

***test*** that it's valid:
```
/usr/sbin/nginx -t -c /etc/nginx/sites-available/healthlocker_staging
```


create a new symlink:
```
sudo ln -s /etc/nginx/sites-available/healthlocker_staging /etc/nginx/sites-enabled/
```

and restart nginx:
```
sudo service nginx restart
```
works:
![image](https://user-images.githubusercontent.com/194400/28152142-c981819c-6796-11e7-9a92-8586c2535f5e.png)




### Trouble-shooting NGINX

if for any reason NGINX is not starting read the logs:
```
tail /var/log/nginx/error.log
```
and google for the issue that is reported.

if you see the following error:
```
nginx: [emerg] open() "/etc/nginx/sites-available/proxy_params" failed (2: No such file or directory)
```
create the file: `/etc/nginx/sites-available/proxy_params`
and paste the following config:
```
proxy_set_header Host $host;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_headers_hash_max_size: 512;
```
found on: https://www.howtoforge.com/how-to-set-up-nginx-as-a-reverse-proxy-for-apache2-on-ubuntu-12.04

## References & Resources

+ http://nginx.org/en/docs/beginners_guide.html
+ https://dennisreimann.de/articles/phoenix-nginx-config.html
+ https://www.digitalocean.com/community/tutorials/how-to-install-nginx-on-ubuntu-16-04
+ https://www.digitalocean.com/community/tutorials/how-to-set-up-nginx-server-blocks-virtual-hosts-on-ubuntu-16-04
+ https://www.digitalocean.com/community/tutorials/how-to-secure-nginx-with-let-s-encrypt-on-ubuntu-16-04
+ https://www.digitalocean.com/community/tutorials/understanding-the-nginx-configuration-file-structure-and-configuration-contexts
+ https://wincent.com/wiki/Checking_nginx_config_file_syntax
+ https://serverfault.com/questions/654957/nginx-emerg-server-directive-is-not-allowed-here-in-etc-nginx-nginx-conf7
+ https://www.digitalocean.com/community/questions/configure-nginx-for-multiple-subdomains
+ https://www.digitalocean.com/community/questions/how-to-create-subdomain-with-nginx-server-in-the-same-droplet
+ https://askubuntu.com/questions/599888/service-nginx-start-is-ok-but-nginx-not-running
+ https://www.digitalocean.com/community/tutorials/how-to-list-and-delete-iptables-firewall-rules
