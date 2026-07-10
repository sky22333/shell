- 一键自动部署异次元发卡
> 适用于`Debian 11+` `Ubuntu 18.04+`系统    基于`Caddy` `php` `mariadb`环境
```
bash <(curl -sSL https://github.com/sky22333/shell/raw/main/web/acgfaka.sh)
```

- 一键自动安装WordPress
> 适用于`Debian 11+` `Ubuntu 18.04+`系统    基于`Caddy` `php` `mariadb`环境
```
bash <(curl -sSL https://github.com/sky22333/shell/raw/main/web/wp.sh)
```

### 完全卸载删除站点及环境
- 删除站点文件
```
sudo rm -r /var/www/
```

- 停止相关服务
```
sudo systemctl stop caddy apache2 mariadb
```

- 禁用开机自启
```
sudo systemctl disable caddy apache2 mariadb
```

- 卸载软件包
```
sudo apt remove --purge caddy apache2 php* mariadb-server mariadb-client -y
```

- 清理残留配置和依赖
```
sudo apt autoremove -y
```
